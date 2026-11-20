-- REVIEW ONLY: NOT APPLIED. Local scratch verification and explicit approval
-- are required before application. No existing job tracking tables are changed.
-- Dedicated runner must hold the existing :eden-migrations lock, skip recorded
-- versions, inspect information_schema before every ADD/CREATE, and verify
-- FK types/collations against users.id and the database default before writes.
-- This file is not intended for execution by a generic SQL split runner.

ALTER TABLE users ADD COLUMN door_to_door_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Text is editable through versioned admin data, not hardcoded in Flutter.
-- Changing consent wording or retention requires a new version; past consent
-- evidence remains tied to the exact version accepted. No policy is activated
-- and no contractor is enabled by this migration.
CREATE TABLE IF NOT EXISTS walking_policy_versions (
  version VARCHAR(40) PRIMARY KEY,
  body TEXT NOT NULL,
  retention_days SMALLINT UNSIGNED NOT NULL DEFAULT 90,
  is_placeholder BOOLEAN NOT NULL DEFAULT TRUE,
  active BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS walking_consents (
  id CHAR(36) PRIMARY KEY,
  contractor_id CHAR(64) NOT NULL,
  consent_version VARCHAR(40) NOT NULL,
  accepted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY walking_consent_identity (contractor_id, consent_version),
  FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (consent_version) REFERENCES walking_policy_versions(version)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS walking_shifts (
  id CHAR(36) PRIMARY KEY,
  contractor_id CHAR(64) NOT NULL,
  started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  ended_at DATETIME(6) NULL DEFAULT NULL,
  status ENUM('active', 'ended') NOT NULL DEFAULT 'active',
  distance_m DECIMAL(12,2) NOT NULL DEFAULT 0,
  consent_id CHAR(36) NOT NULL,
  -- Enforces one active shift per contractor, including concurrent requests.
  -- VIRTUAL preserves cascading FKs on contractor_id: MySQL disallows those
  -- cascades when contractor_id is a base column of a STORED generated column.
  active_contractor_id CHAR(64) GENERATED ALWAYS AS (
    CASE WHEN status = 'active' THEN contractor_id ELSE NULL END
  ) VIRTUAL,
  UNIQUE KEY walking_one_active_shift (active_contractor_id),
  INDEX walking_contractor_date (contractor_id, started_at),
  INDEX walking_status_started (status, started_at),
  INDEX walking_retention (ended_at),
  FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (consent_id) REFERENCES walking_consents(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS walking_points (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  shift_id CHAR(36) NOT NULL,
  -- Sequence numbers make batch retries idempotent without duplicated distance.
  sequence_no INT UNSIGNED NOT NULL,
  latitude DOUBLE NOT NULL,
  longitude DOUBLE NOT NULL,
  accuracy_m DOUBLE NOT NULL,
  recorded_at DATETIME(6) NOT NULL,
  gap_before BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE KEY walking_point_sequence (shift_id, sequence_no),
  INDEX walking_point_time (shift_id, recorded_at),
  FOREIGN KEY (shift_id) REFERENCES walking_shifts(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Only after every preceding operation succeeds:
INSERT IGNORE INTO schema_migrations (version) VALUES ('003_walking_shifts');

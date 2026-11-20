-- REVIEW ONLY: not executed. Apply only after backup verification and approval.
-- The runner must skip this version if recorded, hold the existing migration
-- lock, and check information_schema before each ADD COLUMN. MySQL DDL is not
-- transactional. This file must not be executed by a generic SQL split runner.
-- Catalog/rule/coupon seed data belongs in a separate idempotent seed script.

CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(80) PRIMARY KEY,
  applied_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

ALTER TABLE services ADD COLUMN service_category VARCHAR(5) NOT NULL DEFAULT 'small';
ALTER TABLE services ADD COLUMN short_description VARCHAR(300) NOT NULL DEFAULT '';
ALTER TABLE services ADD COLUMN image_url VARCHAR(500) NULL DEFAULT NULL;
ALTER TABLE services ADD COLUMN estimated_duration_minutes INT UNSIGNED NOT NULL DEFAULT 60;
ALTER TABLE services ADD COLUMN minimum_price_cents INT UNSIGNED NOT NULL DEFAULT 0;
ALTER TABLE services ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'CAD';

-- Existing price_cents remains the base price, with no changes to its values.
-- A zero minimum introduces no new minimum charge for existing services.
-- Duration 60 is a provisional display default, not a scheduling constraint.

ALTER TABLE bookings ADD COLUMN service_category VARCHAR(5) NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN quoted_total_cents INT UNSIGNED NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'CAD';

-- Only populate missing snapshots. Leave existing details JSON untouched.
UPDATE bookings b
LEFT JOIN services s ON s.id = JSON_UNQUOTE(JSON_EXTRACT(b.details, '$.service'))
SET b.service_category = COALESCE(s.service_category, 'small')
WHERE b.service_category IS NULL;

UPDATE bookings
SET quoted_total_cents = CAST(ROUND(CAST(JSON_UNQUOTE(JSON_EXTRACT(details, '$.total')) AS DECIMAL(14,2)) * 100) AS UNSIGNED)
WHERE quoted_total_cents IS NULL
  AND JSON_TYPE(JSON_EXTRACT(details, '$.total')) IN ('INTEGER', 'DOUBLE', 'DECIMAL')
  AND CAST(JSON_UNQUOTE(JSON_EXTRACT(details, '$.total')) AS DECIMAL(14,2)) >= 0;

CREATE TABLE IF NOT EXISTS contractor_services (
  user_id CHAR(64) NOT NULL,
  service_id VARCHAR(20) NOT NULL,
  PRIMARY KEY (user_id, service_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS add_ons (
  id VARCHAR(40) PRIMARY KEY,
  service_id VARCHAR(20) NOT NULL,
  name VARCHAR(100) NOT NULL,
  price_cents INT UNSIGNED NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  FOREIGN KEY (service_id) REFERENCES services(id)
) ENGINE=InnoDB;

-- Service-scoped modifiers: property_size, driveway_size or snow_depth.
-- The application validates dimensions and choices. Legacy pricing stays in
-- its compatibility path, including its existing size, urgent and walkway fees.
CREATE TABLE IF NOT EXISTS service_price_modifiers (
  service_id VARCHAR(20) NOT NULL,
  dimension VARCHAR(30) NOT NULL,
  choice VARCHAR(30) NOT NULL,
  price_cents INT UNSIGNED NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (service_id, dimension, choice),
  FOREIGN KEY (service_id) REFERENCES services(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS city_tax_rates (
  city_id INT PRIMARY KEY,
  rate_bps SMALLINT UNSIGNED NOT NULL,
  FOREIGN KEY (city_id) REFERENCES cities(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS coupons (
  code VARCHAR(40) PRIMARY KEY,
  discount_bps SMALLINT UNSIGNED NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at DATETIME(6) NULL DEFAULT NULL,
  max_uses INT UNSIGNED NULL DEFAULT NULL,
  uses INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS coupon_redemptions (
  booking_id INT PRIMARY KEY,
  coupon_code VARCHAR(40) NOT NULL,
  customer_id CHAR(64) NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  FOREIGN KEY (booking_id) REFERENCES bookings(id),
  FOREIGN KEY (coupon_code) REFERENCES coupons(code),
  FOREIGN KEY (customer_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Record only once every preceding statement has succeeded.
INSERT IGNORE INTO schema_migrations (version) VALUES ('002_services_pricing');

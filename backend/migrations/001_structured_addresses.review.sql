-- REVIEW ONLY. No application has been made.
-- The versioned runner will check information_schema before each ALTER.
-- Existing details JSON and all current columns remain intact.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(80) PRIMARY KEY,
  applied_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS cities (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  state VARCHAR(150) NOT NULL DEFAULT '',
  country VARCHAR(100) NOT NULL,
  latitude DOUBLE NULL,
  longitude DOUBLE NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE KEY city_identity (name, state, country)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Execute only when the respective column does not exist:
ALTER TABLE properties ADD COLUMN city_id INT NULL DEFAULT NULL;
ALTER TABLE users ADD COLUMN city_id INT NULL DEFAULT NULL;

-- The runner will check constraint names before adding them:
ALTER TABLE properties ADD CONSTRAINT fk_properties_city
  FOREIGN KEY (city_id) REFERENCES cities(id);
ALTER TABLE users ADD CONSTRAINT fk_users_city
  FOREIGN KEY (city_id) REFERENCES cities(id);

-- Record only after successful completion of every migration statement:
INSERT IGNORE INTO schema_migrations (version) VALUES ('001_structured_addresses');

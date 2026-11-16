import mysql from 'mysql2/promise';

const schema = [
  `CREATE TABLE IF NOT EXISTS services (
    id VARCHAR(20) PRIMARY KEY, title VARCHAR(100) NOT NULL, price_cents INT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS users (
    id CHAR(64) PRIMARY KEY, email VARCHAR(254) NOT NULL UNIQUE, password VARCHAR(161) NOT NULL,
    name VARCHAR(100) NOT NULL, phone VARCHAR(35) NOT NULL, role VARCHAR(12) NOT NULL,
    customer BOOLEAN NOT NULL, contractor BOOLEAN NOT NULL,
    area VARCHAR(150) NOT NULL, service VARCHAR(80) NOT NULL, blocked BOOLEAN NOT NULL DEFAULT FALSE, default_property INT NULL
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS contractor_reviews (
    user_id CHAR(64) PRIMARY KEY, status VARCHAR(12) NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS password_resets (
    token CHAR(64) PRIMARY KEY, user_id CHAR(64) NOT NULL, expires BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS sessions (
    token CHAR(64) PRIMARY KEY, user_id CHAR(64) NOT NULL, expires BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS support (
    id CHAR(64) PRIMARY KEY, user_id CHAR(64) NOT NULL, description VARCHAR(1000) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Open', created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS properties (
    id INT AUTO_INCREMENT PRIMARY KEY, owner CHAR(64) NOT NULL, details JSON NOT NULL,
    FOREIGN KEY (owner) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS bookings (
    id INT AUTO_INCREMENT PRIMARY KEY, customer_id CHAR(64), contractor_id CHAR(64),
    status VARCHAR(20) NOT NULL DEFAULT 'searching', version INT NOT NULL DEFAULT 0,
    details JSON NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX (status, contractor_id)
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS booking_locations (
    booking_id INT PRIMARY KEY, latitude DOUBLE NOT NULL, longitude DOUBLE NOT NULL,
    shared_at BIGINT NOT NULL,
    FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS payment_orders (
    id CHAR(36) PRIMARY KEY, booking_id INT NOT NULL, customer_id CHAR(64) NOT NULL,
    kind VARCHAR(12) NOT NULL, amount_cents INT NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'pending',
    stripe_intent VARCHAR(255), stripe_session VARCHAR(255),
    UNIQUE KEY booking_kind (booking_id, kind)
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS weekly_runs (
    source_id INT NOT NULL, scheduled_at BIGINT NOT NULL, PRIMARY KEY (source_id, scheduled_at),
    FOREIGN KEY (source_id) REFERENCES bookings(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS account_images (
    user_id CHAR(64) NOT NULL, kind VARCHAR(20) NOT NULL, data MEDIUMTEXT NOT NULL,
    PRIMARY KEY (user_id, kind),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS preferences (
    user_id CHAR(64) PRIMARY KEY, details JSON NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS declined_jobs (
    booking_id INT NOT NULL, contractor_id CHAR(64) NOT NULL, PRIMARY KEY (booking_id, contractor_id),
    FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE,
    FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
];

export async function openDatabase(uri) {
  if (!uri) throw new Error('Set EDEN_MYSQL_URL to the MySQL database connection URL.');
  const config = new URL(uri);
  if (config.protocol !== 'mysql:') throw new Error('EDEN_MYSQL_URL must use mysql://.');
  const pool = mysql.createPool({
    host: config.hostname, port: Number(config.port || 3306),
    user: decodeURIComponent(config.username), password: decodeURIComponent(config.password),
    database: decodeURIComponent(config.pathname.slice(1)),
    charset: 'utf8mb4', connectionLimit: 10,
    ...(config.searchParams.get('tls') === 'true' ? { ssl: { rejectUnauthorized: true } } : {}),
  });
  try {
    for (const statement of schema) await pool.query(statement);
    for (const entry of [['snow', 'Snow Removal', 4500], ['lawn', 'Lawn Mowing', 3000], ['cleaning', 'House Cleaning', 8500]]) {
      await pool.execute('INSERT IGNORE INTO services (id, title, price_cents) VALUES (?, ?, ?)', entry);
    }
    return pool;
  } catch (error) {
    await pool.end();
    throw error;
  }
}

import { readFile } from 'node:fs/promises';

// Importing this module never applies a migration. Application is explicitly gated.
export async function addressesReady(db) {
  const [rows] = await db.execute(
    "SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_migrations'",
  );
  if (!rows[0].n) return false;
  const [applied] = await db.execute("SELECT version FROM schema_migrations WHERE version = '001_structured_addresses'");
  return applied.length === 1;
}

export async function runAddressMigration(db) {
  const connection = await db.getConnection();
  try {
    const [[lock]] = await connection.query("SELECT GET_LOCK(CONCAT(DATABASE(), ':eden-migrations'), 20) AS acquired");
    if (lock.acquired !== 1) throw new Error('Could not acquire migration lock.');
    if (await versionApplied(connection, '001_structured_addresses')) {
      return { version: '001_structured_addresses', status: 'skipped' };
    }
    const sql = await readFile(new URL('./001_structured_addresses.review.sql', import.meta.url), 'utf8');
    const statements = sql.split(String.fromCharCode(10))
      .map(line => line.startsWith('--') ? '' : line).join(String.fromCharCode(10))
      .split(';').map(value => value.trim()).filter(Boolean);
    for (const statement of statements) {
      const column = /^ALTER TABLE (properties|users) ADD COLUMN city_id/.exec(statement);
      if (column) {
        const [[existing]] = await connection.execute(
          "SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'city_id'",
          [column[1]],
        );
        if (existing.n) continue;
      }
      const foreign = /^ALTER TABLE (properties|users) ADD CONSTRAINT ([a-z_]+)/.exec(statement);
      if (foreign) {
        const [[existing]] = await connection.execute(
          'SELECT COUNT(*) AS n FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = ? AND CONSTRAINT_NAME = ?',
          [foreign[1], foreign[2]],
        );
        if (existing.n) continue;
      }
      await connection.query(statement);
    }
  } finally {
    await connection.query("SELECT RELEASE_LOCK(CONCAT(DATABASE(), ':eden-migrations'))").catch(() => {});
    connection.release();
  }
}

async function tableExists(connection, table) {
  const [[row]] = await connection.execute(
    'SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
    [table],
  );
  return Number(row.n) > 0;
}

async function versionApplied(connection, version) {
  if (!await tableExists(connection, 'schema_migrations')) return false;
  const [rows] = await connection.execute('SELECT version FROM schema_migrations WHERE version = ?', [version]);
  return rows.length > 0;
}

// Dedicated, reviewed 002 handler. Never reads/splits arbitrary SQL files and
// never runs on import or startup. DDL auto-commits: incomplete runs resume by
// checking metadata; only the final successful statement records the version.
export async function runServicesPricingMigration(db) {
  const connection = await db.getConnection();
  let locked = false;
  const version = '002_services_pricing';
  try {
    const [[lock]] = await connection.query("SELECT GET_LOCK(CONCAT(DATABASE(), ':eden-migrations'), 20) AS acquired");
    if (lock.acquired !== 1) throw new Error('Could not acquire migration lock.');
    locked = true;
    if (await versionApplied(connection, version)) return { version, status: 'skipped' };

    async function createTable(table, definition) {
      if (!await tableExists(connection, table)) {
        await connection.query(`CREATE TABLE IF NOT EXISTS ${table} (${definition}) ENGINE=InnoDB`);
      }
    }
    async function addColumn(table, column, definition) {
      const [[row]] = await connection.execute(
        'SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        [table, column],
      );
      if (!Number(row.n)) await connection.query(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    }

    await createTable('schema_migrations', `version VARCHAR(80) PRIMARY KEY,
      applied_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)`);
    for (const [column, definition] of [
      ['service_category', "VARCHAR(5) NOT NULL DEFAULT 'small'"],
      ['short_description', "VARCHAR(300) NOT NULL DEFAULT ''"],
      ['image_url', 'VARCHAR(500) NULL DEFAULT NULL'],
      ['estimated_duration_minutes', 'INT UNSIGNED NOT NULL DEFAULT 60'],
      ['minimum_price_cents', 'INT UNSIGNED NOT NULL DEFAULT 0'],
      ['currency', "CHAR(3) NOT NULL DEFAULT 'CAD'"],
    ]) await addColumn('services', column, definition);
    for (const [column, definition] of [
      ['service_category', 'VARCHAR(5) NULL DEFAULT NULL'],
      ['quoted_total_cents', 'INT UNSIGNED NULL DEFAULT NULL'],
      ['currency', "CHAR(3) NOT NULL DEFAULT 'CAD'"],
    ]) await addColumn('bookings', column, definition);

    await connection.query(`UPDATE bookings b
      LEFT JOIN services s ON s.id = JSON_UNQUOTE(JSON_EXTRACT(b.details, '$.service'))
      SET b.service_category = COALESCE(s.service_category, 'small')
      WHERE b.service_category IS NULL`);
    await connection.query(`UPDATE bookings
      SET quoted_total_cents = CAST(ROUND(CAST(JSON_UNQUOTE(JSON_EXTRACT(details, '$.total')) AS DECIMAL(14,2)) * 100) AS UNSIGNED)
      WHERE quoted_total_cents IS NULL
        AND JSON_TYPE(JSON_EXTRACT(details, '$.total')) IN ('INTEGER', 'DOUBLE', 'DECIMAL')
        AND CAST(JSON_UNQUOTE(JSON_EXTRACT(details, '$.total')) AS DECIMAL(14,2)) >= 0`);

    await createTable('contractor_services', `user_id CHAR(64) NOT NULL,
      service_id VARCHAR(20) NOT NULL, PRIMARY KEY (user_id, service_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (service_id) REFERENCES services(id)`);
    await createTable('add_ons', `id VARCHAR(40) PRIMARY KEY,
      service_id VARCHAR(20) NOT NULL, name VARCHAR(100) NOT NULL,
      price_cents INT UNSIGNED NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE,
      FOREIGN KEY (service_id) REFERENCES services(id)`);
    await createTable('service_price_modifiers', `service_id VARCHAR(20) NOT NULL,
      dimension VARCHAR(30) NOT NULL, choice VARCHAR(30) NOT NULL,
      price_cents INT UNSIGNED NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE,
      PRIMARY KEY (service_id, dimension, choice),
      FOREIGN KEY (service_id) REFERENCES services(id)`);
    await createTable('city_tax_rates', `city_id INT PRIMARY KEY,
      rate_bps SMALLINT UNSIGNED NOT NULL, FOREIGN KEY (city_id) REFERENCES cities(id)`);
    await createTable('coupons', `code VARCHAR(40) PRIMARY KEY,
      discount_bps SMALLINT UNSIGNED NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE,
      expires_at DATETIME(6) NULL DEFAULT NULL, max_uses INT UNSIGNED NULL DEFAULT NULL,
      uses INT UNSIGNED NOT NULL DEFAULT 0`);
    await createTable('coupon_redemptions', `booking_id INT PRIMARY KEY,
      coupon_code VARCHAR(40) NOT NULL, customer_id CHAR(64) NULL,
      created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
      FOREIGN KEY (booking_id) REFERENCES bookings(id),
      FOREIGN KEY (coupon_code) REFERENCES coupons(code),
      FOREIGN KEY (customer_id) REFERENCES users(id) ON DELETE SET NULL`);
    await connection.query("INSERT IGNORE INTO schema_migrations (version) VALUES ('002_services_pricing')");
    return { version, status: 'applied' };
  } finally {
    try {
      if (locked) await connection.query("SELECT RELEASE_LOCK(CONCAT(DATABASE(), ':eden-migrations'))");
    } finally {
      connection.release();
    }
  }
}

// Dedicated 003 handler. Explicit reviewed statements, no automatic application.
export async function runWalkingMigration(db) {
  const c = await db.getConnection();
  let locked = false;
  const version = '003_walking_shifts';
  try {
    const [[lock]] = await c.query("SELECT GET_LOCK(CONCAT(DATABASE(), ':eden-migrations'), 20) AS acquired");
    if (lock.acquired !== 1) throw new Error('Could not acquire migration lock.');
    locked = true;
    if (await versionApplied(c, version)) return { version, status: 'skipped' };
    const [[schema]] = await c.query('SELECT DEFAULT_CHARACTER_SET_NAME AS charset_name, DEFAULT_COLLATION_NAME AS collation_name FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=DATABASE()');
    const [[userId]] = await c.query("SELECT COLUMN_TYPE,CHARACTER_SET_NAME,COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='id'");
    if (!userId || userId.COLUMN_TYPE.toLowerCase() !== 'char(64)' || userId.CHARACTER_SET_NAME !== schema.charset_name || userId.COLLATION_NAME !== schema.collation_name) {
      throw new Error('Walking foreign-key preflight failed. No schema changes attempted.');
    }
    const [[flag]] = await c.execute("SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='door_to_door_enabled'");
    if (!Number(flag.n)) await c.query('ALTER TABLE users ADD COLUMN door_to_door_enabled BOOLEAN NOT NULL DEFAULT FALSE');
    const tables = [
      ['walking_policy_versions', `version VARCHAR(40) PRIMARY KEY, body TEXT NOT NULL,
        retention_days SMALLINT UNSIGNED NOT NULL DEFAULT 90,
        is_placeholder BOOLEAN NOT NULL DEFAULT TRUE, active BOOLEAN NOT NULL DEFAULT FALSE,
        created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)`],
      ['walking_consents', `id CHAR(36) PRIMARY KEY, contractor_id CHAR(64) NOT NULL,
        consent_version VARCHAR(40) NOT NULL, accepted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        UNIQUE KEY walking_consent_identity (contractor_id, consent_version),
        FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (consent_version) REFERENCES walking_policy_versions(version)`],
      ['walking_shifts', `id CHAR(36) PRIMARY KEY, contractor_id CHAR(64) NOT NULL,
        started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), ended_at DATETIME(6) NULL DEFAULT NULL,
        status ENUM('active', 'ended') NOT NULL DEFAULT 'active', distance_m DECIMAL(12,2) NOT NULL DEFAULT 0,
        consent_id CHAR(36) NOT NULL,
        active_contractor_id CHAR(64) GENERATED ALWAYS AS (CASE WHEN status = 'active' THEN contractor_id ELSE NULL END) VIRTUAL,
        UNIQUE KEY walking_one_active_shift (active_contractor_id),
        INDEX walking_contractor_date (contractor_id, started_at),
        INDEX walking_status_started (status, started_at), INDEX walking_retention (ended_at),
        FOREIGN KEY (contractor_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (consent_id) REFERENCES walking_consents(id) ON DELETE CASCADE`],
      ['walking_points', `id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, shift_id CHAR(36) NOT NULL,
        sequence_no INT UNSIGNED NOT NULL, latitude DOUBLE NOT NULL, longitude DOUBLE NOT NULL,
        accuracy_m DOUBLE NOT NULL, recorded_at DATETIME(6) NOT NULL, gap_before BOOLEAN NOT NULL DEFAULT FALSE,
        UNIQUE KEY walking_point_sequence (shift_id, sequence_no), INDEX walking_point_time (shift_id, recorded_at),
        FOREIGN KEY (shift_id) REFERENCES walking_shifts(id) ON DELETE CASCADE`],
    ];
    for (const [table, definition] of tables) {
      if (!await tableExists(c, table)) await c.query(`CREATE TABLE IF NOT EXISTS ${table} (${definition}) ENGINE=InnoDB`);
    }
    const [keys] = await c.query(`SELECT a.COLUMN_TYPE AS child_type,a.CHARACTER_SET_NAME AS child_charset,a.COLLATION_NAME AS child_collation,
      p.COLUMN_TYPE AS parent_type,p.CHARACTER_SET_NAME AS parent_charset,p.COLLATION_NAME AS parent_collation
      FROM information_schema.KEY_COLUMN_USAGE k
      JOIN information_schema.COLUMNS a ON a.TABLE_SCHEMA=k.TABLE_SCHEMA AND a.TABLE_NAME=k.TABLE_NAME AND a.COLUMN_NAME=k.COLUMN_NAME
      JOIN information_schema.COLUMNS p ON p.TABLE_SCHEMA=k.REFERENCED_TABLE_SCHEMA AND p.TABLE_NAME=k.REFERENCED_TABLE_NAME AND p.COLUMN_NAME=k.REFERENCED_COLUMN_NAME
      WHERE k.TABLE_SCHEMA=DATABASE() AND k.TABLE_NAME IN ('walking_consents','walking_shifts','walking_points') AND k.REFERENCED_TABLE_NAME IS NOT NULL`);
    if (keys.length !== 5 || keys.some(k => k.child_type !== k.parent_type || k.child_charset !== k.parent_charset || k.child_collation !== k.parent_collation)) {
      throw new Error('Walking foreign-key metadata verification failed; migration not recorded.');
    }
    await c.query("INSERT IGNORE INTO schema_migrations (version) VALUES ('003_walking_shifts')");
    return { version, status: 'applied', foreignKeysChecked: keys.length };
  } finally {
    try { if (locked) await c.query("SELECT RELEASE_LOCK(CONCAT(DATABASE(), ':eden-migrations'))"); }
    finally { c.release(); }
  }
}



// Dedicated 004 handler for large-job dispatch.
// This function is never executed on import or automatically by startup.
export async function runLargeJobsDispatchMigration(db) {
  const c = await db.getConnection();
  let locked = false;
  const version = '004_large_jobs_dispatch';

  try {
    const [[lock]] = await c.query(
      "SELECT GET_LOCK(CONCAT(DATABASE(), ':eden-migrations'), 20) AS acquired",
    );
    if (lock.acquired !== 1) throw new Error('Could not acquire migration lock.');
    locked = true;

    if (await versionApplied(c, version)) return { version, status: 'skipped' };

    // Verify users.id and bookings defaults before any schema changes.
    const [[userId]] = await c.query(
      "SELECT COLUMN_TYPE, CHARACTER_SET_NAME, COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='id'",
    );
    const [[bookingsTable]] = await c.query(
      "SELECT TABLE_COLLATION AS collation_name FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bookings'",
    );

    if (
      !userId ||
      userId.COLUMN_TYPE.toLowerCase() !== 'char(64)' ||
      !userId.CHARACTER_SET_NAME ||
      !userId.COLLATION_NAME ||
      !bookingsTable ||
      bookingsTable.collation_name !== userId.COLLATION_NAME
    ) {
      throw new Error('Large-job dispatch foreign-key preflight failed. No schema changes attempted.');
    }

    // Check existing assignment columns directly against users.id.
    const [existingAssignmentColumns] = await c.query(
      "SELECT COLUMN_NAME, COLUMN_TYPE, CHARACTER_SET_NAME, COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bookings' AND COLUMN_NAME IN ('assigned_contractor_id','assigned_by_admin_id')",
    );
    for (const row of existingAssignmentColumns) {
      if (
        row.COLUMN_TYPE.toLowerCase() !== userId.COLUMN_TYPE.toLowerCase() ||
        row.CHARACTER_SET_NAME !== userId.CHARACTER_SET_NAME ||
        row.COLLATION_NAME !== userId.COLLATION_NAME
      ) {
        throw new Error(`Large-job dispatch preflight failed for bookings.${row.COLUMN_NAME}. No schema changes attempted.`);
      }
    }

    // Ensure migration tracking exists after all preflight checks pass.
    if (!await tableExists(c, 'schema_migrations')) {
      await c.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(80) PRIMARY KEY,
        applied_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
      ) ENGINE=InnoDB`);
    }

    const columns = [
      ['dispatch_status', "ENUM('open','pending_admin','assigned','rejected') NOT NULL DEFAULT 'open'"],
      ['assigned_contractor_id', 'CHAR(64) NULL DEFAULT NULL'],
      ['assigned_by_admin_id', 'CHAR(64) NULL DEFAULT NULL'],
      ['assigned_at', 'DATETIME(6) NULL DEFAULT NULL'],
      ['admin_note', 'TEXT NULL DEFAULT NULL'],
      ['rejection_reason', 'TEXT NULL DEFAULT NULL'],
    ];

    for (const [column, definition] of columns) {
      const [[row]] = await c.execute(
        'SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
        ['bookings', column],
      );
      if (!Number(row.n)) {
        await c.query(`ALTER TABLE bookings ADD COLUMN ${column} ${definition}`);
      }
    }

    const indexes = [
      ['idx_bookings_dispatch_status', 'dispatch_status'],
      ['idx_bookings_assigned_contractor', 'assigned_contractor_id'],
    ];

    for (const [name, column] of indexes) {
      const [[row]] = await c.execute(
        'SELECT COUNT(*) AS n FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND INDEX_NAME=?',
        ['bookings', name],
      );
      if (!Number(row.n)) {
        await c.query(`CREATE INDEX ${name} ON bookings (${column})`);
      }
    }

    const foreignKeys = [
      ['fk_bookings_assigned_contractor', 'assigned_contractor_id'],
      ['fk_bookings_assigned_admin', 'assigned_by_admin_id'],
    ];

    for (const [name, column] of foreignKeys) {
      const [[row]] = await c.execute(
        "SELECT COUNT(*) AS n FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA=DATABASE() AND TABLE_NAME=? AND CONSTRAINT_NAME=? AND CONSTRAINT_TYPE='FOREIGN KEY'",
        ['bookings', name],
      );
      if (!Number(row.n)) {
        await c.query(
          `ALTER TABLE bookings ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES users(id) ON DELETE SET NULL`,
        );
      }
    }

    // Verify all six columns and their expected definitions.
    const [actualColumns] = await c.query(
      "SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bookings' AND COLUMN_NAME IN ('dispatch_status','assigned_contractor_id','assigned_by_admin_id','assigned_at','admin_note','rejection_reason')",
    );
    const expectedTypes = new Map([
      ['dispatch_status', "enum('open','pending_admin','assigned','rejected')"],
      ['assigned_contractor_id', 'char(64)'],
      ['assigned_by_admin_id', 'char(64)'],
      ['assigned_at', 'datetime(6)'],
      ['admin_note', 'text'],
      ['rejection_reason', 'text'],
    ]);

    if (
      actualColumns.length !== expectedTypes.size ||
      actualColumns.some(row =>
        row.COLUMN_TYPE.toLowerCase() !== expectedTypes.get(row.COLUMN_NAME) ||
        (row.COLUMN_NAME !== 'dispatch_status' && row.IS_NULLABLE !== 'YES')
      )
    ) {
      throw new Error('Large-job dispatch column verification failed; migration not recorded.');
    }

    // Verify each index is on the intended column.
    const [actualIndexes] = await c.query(
      "SELECT INDEX_NAME, COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bookings' AND INDEX_NAME IN ('idx_bookings_dispatch_status','idx_bookings_assigned_contractor') AND SEQ_IN_INDEX=1",
    );
    if (
      indexes.some(([name, column]) =>
        !actualIndexes.some(row => row.INDEX_NAME === name && row.COLUMN_NAME === column)
      )
    ) {
      throw new Error('Large-job dispatch index verification failed; migration not recorded.');
    }

    // Verify both foreign keys point to users.id.
    const [actualForeignKeys] = await c.query(
      "SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bookings' AND CONSTRAINT_NAME IN ('fk_bookings_assigned_contractor','fk_bookings_assigned_admin')",
    );
    if (
      actualForeignKeys.length !== 2 ||
      foreignKeys.some(([name, column]) =>
        !actualForeignKeys.some(row =>
          row.CONSTRAINT_NAME === name &&
          row.COLUMN_NAME === column &&
          row.REFERENCED_TABLE_NAME === 'users' &&
          row.REFERENCED_COLUMN_NAME === 'id'
        )
      )
    ) {
      throw new Error('Large-job dispatch foreign-key verification failed; migration not recorded.');
    }

    await c.query(
      "INSERT IGNORE INTO schema_migrations (version) VALUES ('004_large_jobs_dispatch')",
    );
    return { version, status: 'applied' };
  } finally {
    try {
      if (locked) {
        await c.query("SELECT RELEASE_LOCK(CONCAT(DATABASE(), ':eden-migrations'))");
      }
    } finally {
      c.release();
    }
  }
}
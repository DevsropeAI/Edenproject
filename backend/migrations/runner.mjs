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

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { runAddressMigration, runServicesPricingMigration } from './migrations/runner.mjs';

test('migration runner skips additive columns and constraints already applied', async () => {
  const statements = [];
  let released = false;
  const connection = {
    query: async sql => {
      if (sql.includes('GET_LOCK')) return [[{ acquired: 1 }]];
      statements.push(sql);
      return [];
    },
    execute: async sql => sql.startsWith('SELECT version') ? [[]] : [[{ n: 1 }]],
    release: () => { released = true; },
  };
  await runAddressMigration({ getConnection: async () => connection });
  assert.equal(statements.some(sql => sql.startsWith('ALTER TABLE')), false);
  assert.ok(statements.some(sql => sql.startsWith('CREATE TABLE IF NOT EXISTS cities')));
  assert.ok(statements.some(sql => sql.startsWith('INSERT IGNORE INTO schema_migrations')));
  assert.equal(released, true);
});

// In-memory database double; these cases do not alter any real database.
function fakeDatabase({ tables = [], columns = [], versions = [] } = {}) {
  const storedTables = new Set(tables);
  const storedColumns = new Set(columns);
  const storedVersions = new Set(versions);
  const statements = [];
  const checks = new Set();
  let released = 0;
  const connection = {
    execute: async (sql, params) => {
      if (sql.includes('information_schema.TABLES')) {
        checks.add('table:' + params[0]);
        return [[{ n: Number(storedTables.has(params[0])) }]];
      }
      if (sql.includes('information_schema.COLUMNS')) {
        checks.add('column:' + params.join('.'));
        return [[{ n: Number(storedColumns.has(params.join('.'))) }]];
      }
      assert.ok(sql.startsWith('SELECT version'));
      return [storedVersions.has(params[0]) ? [{ version: params[0] }] : []];
    },
    query: async sql => {
      if (sql.includes('GET_LOCK')) return [[{ acquired: 1 }]];
      statements.push(sql);
      const table = /^CREATE TABLE IF NOT EXISTS ([a-z_]+)/.exec(sql);
      if (table) {
        assert.ok(checks.has('table:' + table[1]));
        assert.equal(storedTables.has(table[1]), false);
        storedTables.add(table[1]);
      }
      const column = /^ALTER TABLE ([a-z_]+) ADD COLUMN ([a-z_]+)/.exec(sql);
      if (column) {
        const key = column[1] + '.' + column[2];
        assert.ok(checks.has('column:' + key));
        assert.equal(storedColumns.has(key), false);
        storedColumns.add(key);
      }
      if (sql.startsWith('INSERT IGNORE INTO schema_migrations')) storedVersions.add('002_services_pricing');
      return [];
    },
    release: () => { released++; },
  };
  return { getConnection: async () => connection, statements, storedColumns, storedTables, released: () => released };
}

test('002 first run applies, records last, and second run skips with metadata checks', async () => {
  const db = fakeDatabase();
  assert.equal((await runServicesPricingMigration(db)).status, 'applied');
  assert.equal(db.storedColumns.size, 9);
  assert.equal(db.storedTables.size, 7);
  assert.match(db.statements.at(-2), /^INSERT IGNORE INTO schema_migrations/);
  const start = db.statements.length;
  assert.equal((await runServicesPricingMigration(db)).status, 'skipped');
  assert.equal(db.statements.length, start + 1); // Unlock only; no writes.
  assert.equal(db.released(), 2);
});

test('002 partially applied case skips existing objects and only adds missing ones', async () => {
  const db = fakeDatabase({ tables: ['schema_migrations', 'contractor_services', 'coupons'],
    columns: ['services.service_category', 'bookings.quoted_total_cents'] });
  assert.equal((await runServicesPricingMigration(db)).status, 'applied');
  assert.equal(db.statements.filter(s => s.startsWith('ALTER TABLE')).length, 7);
  assert.equal(db.statements.filter(s => s.startsWith('CREATE TABLE')).length, 4);
  assert.equal(db.storedColumns.size, 9);
  assert.equal(db.storedTables.size, 7);
  assert.ok(db.statements.filter(s => s.startsWith('UPDATE bookings')).every(s => s.includes('IS NULL')));
  assert.equal((await runServicesPricingMigration(db)).status, 'skipped');
});

test('001 applied version skips without DDL or backfills', async () => {
  const db = fakeDatabase({ tables: ['schema_migrations'], versions: ['001_structured_addresses'] });
  assert.equal((await runAddressMigration(db)).status, 'skipped');
  assert.equal(db.statements.length, 1);
  assert.ok(db.statements[0].includes('RELEASE_LOCK'));
});



import { runLargeJobsDispatchMigration } from './migrations/runner.mjs';

function largeJobsMigrationFake({
  applied = false,
  compatibleUserId = true,
  compatibleBookingsCollation = true,
  hasMigrationTable = true,
} = {}) {
  const statements = [];
  let recorded = applied;
  let released = 0;

  const expectedColumns = [
    { COLUMN_NAME: 'dispatch_status', COLUMN_TYPE: "enum('open','pending_admin','assigned','rejected')", IS_NULLABLE: 'NO' },
    { COLUMN_NAME: 'assigned_contractor_id', COLUMN_TYPE: 'char(64)', IS_NULLABLE: 'YES' },
    { COLUMN_NAME: 'assigned_by_admin_id', COLUMN_TYPE: 'char(64)', IS_NULLABLE: 'YES' },
    { COLUMN_NAME: 'assigned_at', COLUMN_TYPE: 'datetime(6)', IS_NULLABLE: 'YES' },
    { COLUMN_NAME: 'admin_note', COLUMN_TYPE: 'text', IS_NULLABLE: 'YES' },
    { COLUMN_NAME: 'rejection_reason', COLUMN_TYPE: 'text', IS_NULLABLE: 'YES' },
  ];

  const expectedIndexes = [
    { INDEX_NAME: 'idx_bookings_dispatch_status', COLUMN_NAME: 'dispatch_status' },
    { INDEX_NAME: 'idx_bookings_assigned_contractor', COLUMN_NAME: 'assigned_contractor_id' },
  ];

  const expectedForeignKeys = [
    { CONSTRAINT_NAME: 'fk_bookings_assigned_contractor', COLUMN_NAME: 'assigned_contractor_id', REFERENCED_TABLE_NAME: 'users', REFERENCED_COLUMN_NAME: 'id' },
    { CONSTRAINT_NAME: 'fk_bookings_assigned_admin', COLUMN_NAME: 'assigned_by_admin_id', REFERENCED_TABLE_NAME: 'users', REFERENCED_COLUMN_NAME: 'id' },
  ];

  const connection = {
    execute: async (sql, params = []) => {
      if (sql.includes('information_schema.TABLES')) {
        return [[{ n: Number(
          params[0] === 'schema_migrations' && hasMigrationTable,
        ) }]];
      }
      if (sql.startsWith('SELECT version')) {
        return [recorded ? [{ version: '004_large_jobs_dispatch' }] : []];
      }
      if (sql.includes('information_schema.COLUMNS')) {
        return [[{ n: 0 }]];
      }
      if (sql.includes('information_schema.STATISTICS')) {
        return [[{ n: 0 }]];
      }
      if (sql.includes('information_schema.TABLE_CONSTRAINTS')) {
        return [[{ n: 0 }]];
      }
      throw new Error(`Unexpected execute in migration 004 test: ${sql}`);
    },

    query: async sql => {
      if (sql.includes('GET_LOCK')) return [[{ acquired: 1 }]];
      if (sql.includes('DEFAULT_CHARACTER_SET_NAME')) {
        return [[{ charset_name: 'utf8mb4', collation_name: 'utf8mb4_unicode_ci' }]];
      }
      if (sql.includes('information_schema.TABLES') && sql.includes("TABLE_NAME='bookings'")) {
        return [[{
          collation_name: compatibleBookingsCollation
            ? 'utf8mb4_unicode_ci'
            : 'utf8mb4_general_ci',
        }]];
      }
      if (sql.includes("TABLE_NAME='users'")) {
        return [[{
          COLUMN_TYPE: compatibleUserId ? 'char(64)' : 'varchar(64)',
          CHARACTER_SET_NAME: 'utf8mb4',
          COLLATION_NAME: 'utf8mb4_unicode_ci',
        }]];
      }
      if (sql.includes("COLUMN_NAME IN ('assigned_contractor_id','assigned_by_admin_id')")) {
        return [[]];
      }
      if (sql.includes("COLUMN_NAME IN ('dispatch_status','assigned_contractor_id'")) {
        return [expectedColumns];
      }
      if (sql.includes("INDEX_NAME IN ('idx_bookings_dispatch_status'")) {
        return [expectedIndexes];
      }
      if (sql.includes("CONSTRAINT_NAME IN ('fk_bookings_assigned_contractor'")) {
        return [expectedForeignKeys];
      }
      if (sql.startsWith('INSERT IGNORE INTO schema_migrations')) {
        statements.push(sql);
        recorded = true;
        return [];
      }
      if (sql.includes('RELEASE_LOCK')) {
        released++;
        return [];
      }
      statements.push(sql);
      return [];
    },

    release: () => {},
  };

  return {
    getConnection: async () => connection,
    statements,
    released: () => released,
    isRecorded: () => recorded,
  };
}

test('004 applies dispatch schema, verifies it, and records version last', async () => {
  const db = largeJobsMigrationFake();

  const result = await runLargeJobsDispatchMigration(db);

  assert.deepEqual(result, {
    version: '004_large_jobs_dispatch',
    status: 'applied',
  });

  assert.equal(
    db.statements.filter(sql => sql.startsWith('ALTER TABLE bookings ADD COLUMN')).length,
    6,
  );
  assert.equal(
    db.statements.filter(sql => sql.startsWith('CREATE INDEX')).length,
    2,
  );
  assert.equal(
    db.statements.filter(sql => sql.startsWith('ALTER TABLE bookings ADD CONSTRAINT')).length,
    2,
  );

  const versionInsert = db.statements.findIndex(
    sql => sql.startsWith('INSERT IGNORE INTO schema_migrations'),
  );
  assert.ok(versionInsert >= 0);
  assert.equal(versionInsert, db.statements.length - 1);
  assert.equal(db.isRecorded(), true);
  assert.equal(db.released(), 1);
});

test('004 already-applied migration skips without schema changes', async () => {
  const db = largeJobsMigrationFake({ applied: true });

  const result = await runLargeJobsDispatchMigration(db);

  assert.deepEqual(result, {
    version: '004_large_jobs_dispatch',
    status: 'skipped',
  });
  assert.equal(db.statements.length, 0);
  assert.equal(db.released(), 1);
});

test('004 incompatible users.id fails preflight before schema changes', async () => {
  const db = largeJobsMigrationFake({ compatibleUserId: false });

  await assert.rejects(
    () => runLargeJobsDispatchMigration(db),
    /foreign-key preflight failed/,
  );

  assert.equal(
    db.statements.some(sql =>
      sql.startsWith('ALTER TABLE') || sql.startsWith('CREATE INDEX'),
    ),
    false,
  );
  assert.equal(
    db.statements.some(sql => sql.startsWith('INSERT IGNORE INTO schema_migrations')),
    false,
  );
  assert.equal(db.isRecorded(), false);
  assert.equal(db.released(), 1);
});

test('004 incompatible bookings collation fails before schema changes', async () => {
  const db = largeJobsMigrationFake({ compatibleBookingsCollation: false });

  await assert.rejects(
    () => runLargeJobsDispatchMigration(db),
    /foreign-key preflight failed/,
  );

  assert.equal(db.statements.length, 0);
  assert.equal(db.isRecorded(), false);
  assert.equal(db.released(), 1);
});

test('004 creates missing migration tracking table after preflight', async () => {
  const db = largeJobsMigrationFake({ hasMigrationTable: false });

  const result = await runLargeJobsDispatchMigration(db);

  assert.deepEqual(result, {
    version: '004_large_jobs_dispatch',
    status: 'applied',
  });

  const trackingTableIndex = db.statements.findIndex(
    sql => sql.startsWith('CREATE TABLE IF NOT EXISTS schema_migrations'),
  );
  const firstSchemaChangeIndex = db.statements.findIndex(
    sql => sql.startsWith('ALTER TABLE bookings ADD COLUMN'),
  );
  const versionInsertIndex = db.statements.findIndex(
    sql => sql.startsWith('INSERT IGNORE INTO schema_migrations'),
  );

  assert.ok(trackingTableIndex >= 0);
  assert.ok(firstSchemaChangeIndex > trackingTableIndex);
  assert.ok(versionInsertIndex > firstSchemaChangeIndex);
  assert.equal(versionInsertIndex, db.statements.length - 1);
  assert.equal(db.isRecorded(), true);
  assert.equal(db.released(), 1);
});
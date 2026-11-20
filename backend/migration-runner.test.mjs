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

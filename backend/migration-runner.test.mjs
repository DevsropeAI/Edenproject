import assert from 'node:assert/strict';
import { test } from 'node:test';
import { runAddressMigration } from './migrations/runner.mjs';

test('migration runner skips additive columns and constraints already applied', async () => {
  const statements = [];
  let released = false;
  const connection = {
    query: async sql => {
      if (sql.includes('GET_LOCK')) return [[{ acquired: 1 }]];
      statements.push(sql);
      return [];
    },
    execute: async () => [[{ n: 1 }]],
    release: () => { released = true; },
  };
  await runAddressMigration({ getConnection: async () => connection });
  assert.equal(statements.some(sql => sql.startsWith('ALTER TABLE')), false);
  assert.ok(statements.some(sql => sql.startsWith('CREATE TABLE IF NOT EXISTS cities')));
  assert.ok(statements.some(sql => sql.startsWith('INSERT IGNORE INTO schema_migrations')));
  assert.equal(released, true);
});

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, statSync, unlinkSync } from 'node:fs';
import { resolve } from 'node:path';

process.loadEnvFile(new URL('../.env', import.meta.url));
const database = new URL(process.env.EDEN_MYSQL_URL);
if (!['127.0.0.1', 'localhost', '[::1]'].includes(database.hostname)) {
  throw new Error('This command is restricted to a local database.');
}
const [operation, fileArgument, target] = process.argv.slice(2);
if (!['backup', 'restore'].includes(operation) || !fileArgument) {
  throw new Error('Usage: node backend/scripts/database-backup.mjs backup FILE [--skip-events] | restore FILE TARGET_DATABASE');
}
const file = resolve(fileArgument);
const bin = process.env.EDEN_MYSQL_BIN ?? 'C:/Program Files/MySQL/MySQL Server 8.0/bin';
const env = {
  ...process.env,
  MYSQL_PWD: process.env.EDEN_BACKUP_PASSWORD ?? decodeURIComponent(database.password),
};
const connection = [
  '--host=' + database.hostname, '--port=' + (database.port || '3306'),
  '--user=' + (process.env.EDEN_BACKUP_USER ?? decodeURIComponent(database.username)),
];
if (operation === 'backup') {
  if (existsSync(file)) throw new Error('Backup file already exists. Choose a new file.');
  mkdirSync(resolve(file, '..'), { recursive: true });
  const result = spawnSync(resolve(bin, 'mysqldump.exe'), [
    ...connection, '--single-transaction', '--quick', '--routines',
    process.argv.slice(2).includes('--skip-events') ? '--skip-events' : '--events',
    '--triggers', '--hex-blob', '--no-tablespaces', '--set-gtid-purged=OFF',
    '--result-file=' + file, database.pathname.slice(1),
  ], { env, encoding: 'utf8' });
  if (result.error || result.status !== 0) {
    if (existsSync(file)) unlinkSync(file);
    throw new Error('Backup failed: ' + (result.error?.message ?? result.stderr));
  }
  const bytes = statSync(file).size;
  if (!bytes) throw new Error('Backup file is empty.');
  console.log(JSON.stringify({ file, bytes, database: database.pathname.slice(1) }));
} else {
  if (!target || !/^[a-zA-Z0-9_]+$/.test(target)) throw new Error('Supply a valid, existing restore database name.');
  if (!existsSync(file) || !statSync(file).size) throw new Error('Backup file is missing or empty.');
  const { openSync, closeSync } = await import('node:fs');
  const descriptor = openSync(file, 'r');
  try {
    const result = spawnSync(resolve(bin, 'mysql.exe'), [
      ...connection, '--default-character-set=utf8mb4', target,
    ], { env, stdio: [descriptor, 'inherit', 'inherit'] });
    if (result.error || result.status !== 0) throw new Error('Restore failed.');
    console.log('Restored into ' + target);
  } finally {
    closeSync(descriptor);
  }
}

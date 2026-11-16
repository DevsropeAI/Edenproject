import { randomBytes } from 'node:crypto';
import { existsSync, writeFileSync } from 'node:fs';
import mysql from 'mysql2/promise';

const envFile = new URL('./.env', import.meta.url);

export async function configureDatabase() {
  if (existsSync(envFile)) process.loadEnvFile(envFile);
  if (process.env.EDEN_MYSQL_URL) return process.env.EDEN_MYSQL_URL;

  const host = '127.0.0.1';
  const port = Number(process.env.EDEN_LARAGON_MYSQL_PORT ?? 3306);
  const password = randomBytes(24).toString('hex');
  const user = 'eden_local_' + randomBytes(5).toString('hex');
  const url = `mysql://${user}:${password}@${host}:${port}/eden`;
  const root = await mysql.createConnection({
    host, port, user: 'root',
    password: process.env.EDEN_LARAGON_ROOT_PASSWORD ?? '',
  }).catch(error => {
    throw new Error(`Could not connect to Laragon MySQL at ${host}:${port} (${error.code}). Start MySQL in Laragon. If root has a password, set EDEN_LARAGON_ROOT_PASSWORD before running the command.`, { cause: error });
  });

  try {
    await root.query('CREATE DATABASE IF NOT EXISTS eden CHARACTER SET utf8mb4');
    await root.query("CREATE USER ?@'127.0.0.1' IDENTIFIED BY ?", [user, password]);
    try {
      await root.query("GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES ON eden.* TO ?@'127.0.0.1'", [user]);
      const key = process.env.EDEN_ADMIN_KEY ?? randomBytes(32).toString('hex');
      writeFileSync(envFile, [
        '',
        'EDEN_MYSQL_URL=' + url,
        'EDEN_ADMIN_KEY=' + JSON.stringify(key),
        'EDEN_ORIGINS=http://localhost:8080',
        '',
      ].join('\n'), { flag: 'a', mode: 0o600 });
    } catch (error) {
      await root.query("DROP USER ?@'127.0.0.1'", [user]);
      throw error;
    }
  } finally {
    await root.end();
  }

  process.loadEnvFile(envFile);
  console.log('Laragon database eden configured. Local settings saved in backend/.env.');
  return process.env.EDEN_MYSQL_URL;
}

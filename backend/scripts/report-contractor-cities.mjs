import mysql from 'mysql2/promise';

// Dry-run by default. Run after city records have been chosen by real users.
process.loadEnvFile(new URL('../.env', import.meta.url));
const db = await mysql.createConnection(process.env.EDEN_MYSQL_URL);
try {
  const [users] = await db.execute('SELECT id, area FROM users WHERE contractor = 1 AND city_id IS NULL');
  const unmatched = [];
  let matched = 0;
  for (const user of users) {
    const [cities] = await db.execute(
      'SELECT id FROM cities WHERE BINARY name = BINARY ? AND active = 1', [user.area],
    );
    if (cities.length !== 1) {
      unmatched.push({ id: user.id, area: user.area, reason: cities.length ? 'ambiguous' : 'no exact city name' });
      continue;
    }
    matched++;
    if (process.argv.includes('--apply')) {
      await db.execute('UPDATE users SET city_id = ? WHERE id = ? AND city_id IS NULL', [cities[0].id, user.id]);
    }
  }
  console.log(JSON.stringify({ applied: process.argv.includes('--apply'), matched, unmatched }, null, 2));
} finally {
  await db.end();
}

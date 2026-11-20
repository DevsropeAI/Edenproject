import mysql from 'mysql2/promise';

// PLACEHOLDER consent wording and 90-day retention assumption: client/legal
// review required before release. This script never enables any contractor.
export const walkingPolicy = {
  version: 'placeholder-v1', retentionDays: 90,
  body: 'PLACEHOLDER — wording and retention need approval before release. During a door-to-door shift, Eden records your GPS positions, their times and accuracy, and the route and distance travelled. Recording starts only after you choose Start shift and stops when you choose Stop shift. Only authorised administrators can view the route. Route points and shift records are kept for up to 90 days after a shift ends, unless deleted sooner. Your consent record is stored separately as evidence of acceptance. On web, keep this page visible: minimising, locking or closing it can interrupt recording, and unsent points in memory are lost if the app closes. A screen wake lock is requested where supported but cannot guarantee continuous tracking.',
};
export async function seedWalking(db) {
  const [migration]=await db.execute("SELECT version FROM schema_migrations WHERE version='003_walking_shifts'");
  if(!migration.length)throw Error('Migration 003 is required.');
  await db.execute(`INSERT IGNORE INTO walking_policy_versions (version,body,retention_days,is_placeholder,active) VALUES (?,?,?,TRUE,TRUE)`,
    [walkingPolicy.version,walkingPolicy.body,walkingPolicy.retentionDays]);
  const [rows]=await db.execute('SELECT * FROM walking_policy_versions WHERE version=?',[walkingPolicy.version]);
  return rows;
}
if(process.argv[1]?.endsWith('seed-walking.mjs')) {
  process.loadEnvFile(new URL('../.env',import.meta.url));
  const uri=new URL(process.env.EDEN_MYSQL_URL);
  if(uri.hostname!=='127.0.0.1'||uri.pathname!=='/eden')throw Error('Local eden only.');
  const db=mysql.createPool(process.env.EDEN_MYSQL_URL);
  try{console.log(JSON.stringify(await seedWalking(db)));}finally{await db.end();}
}

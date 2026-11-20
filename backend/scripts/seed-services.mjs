import mysql from 'mysql2/promise';

// ALL new prices, minimums, durations, add-ons, modifiers, tax rates and EDEN5
// below are DEVELOPMENT PLACEHOLDERS, pending client approval. No existing
// record is overwritten. Categories other than snow/lawn/tree are provisional.
export const serviceSeeds = [
  ['drivewaySnow', 'Driveway Snow Clearing', 'small', 4000],
  ['walkwayClear', 'Walkway Clearing', 'small', 2000],
  ['entranceClear', 'Front Entrance Clearing', 'small', 2500],
  ['leaf', 'Leaf Removal', 'small', 4000],
  ['tree', 'Tree Trimming', 'small', 7500],
  ['landscaping', 'Landscaping', 'small', 8000],
  ['yard', 'Yard Cleaning', 'small', 5000],
  ['pressure', 'Pressure Washing', 'small', 9000],
  ['gutter', 'Gutter Cleaning', 'small', 6500],
  ['hardscaping', 'Hardscaping', 'large', 30000],
  ['paver', 'Paver Installation', 'large', 40000],
  ['drivewayBuild', 'Driveway Construction', 'large', 50000],
  ['walkwayBuild', 'Walkway Construction', 'large', 25000],
  ['retainingWall', 'Retaining Wall Installation', 'large', 45000],
];

export async function seedServices(db) {
  const c = await db.getConnection();
  const inserted = { services: 0, addOns: 0, modifiers: 0, taxes: 0, coupons: 0 };
  try {
    await c.beginTransaction();
    const [[migration]] = await c.execute("SELECT version FROM schema_migrations WHERE version = '002_services_pricing'");
    if (!migration) throw new Error('Apply approved migration 002 before seeding.');
    async function insert(key, sql, values = []) {
      const [result] = await c.execute(sql, values); inserted[key] += result.affectedRows;
    }
    for (const [id, title, category, cents] of serviceSeeds) {
      await insert('services', `INSERT IGNORE INTO services
        (id,title,price_cents,active,service_category,short_description,estimated_duration_minutes,minimum_price_cents,currency)
        VALUES (?,?,?,1,?,?,60,?,'CAD')`, [id,title,cents,category,'Placeholder pricing — contact Eden for confirmed rates.',cents]);
      await insert('addOns', 'INSERT IGNORE INTO add_ons (id,service_id,name,price_cents,active) VALUES (?,?,?,?,1)',
        [id + '-extra',id,'Extra service time (placeholder)',1000]);
      for (const [dimension, choice, price] of [
        ['property_size','Large',1500], ['driveway_size','small',0],
        ['driveway_size','medium',500], ['driveway_size','large',1500],
        ...(['drivewaySnow','walkwayClear','entranceClear'].includes(id)
          ? [['snow_depth','light',0],['snow_depth','moderate',1000],['snow_depth','heavy',2500]] : []),
      ]) await insert('modifiers', `INSERT IGNORE INTO service_price_modifiers
        (service_id,dimension,choice,price_cents,active) VALUES (?,?,?,?,1)`, [id,dimension,choice,price]);
    }
    // Existing snow walkway remains CAD 12; the quote engine must not double count.
    await insert('addOns', `INSERT IGNORE INTO add_ons (id,service_id,name,price_cents,active)
      VALUES ('snow-walkway','snow','Walkway clearing',1200,1)`);
    // Test rates only, not a statement about jurisdictional tax law. Used only
    // for added services: original three always retain their existing 13%.
    await insert('taxes', `INSERT IGNORE INTO city_tax_rates (city_id,rate_bps)
      SELECT id, CASE WHEN MOD(id,2)=0 THEN 500 ELSE 1300 END FROM cities WHERE active=1`);
    for (const row of [
      ['EDEN10',1000,null,null,0],
      ['EDEN5',500,'2099-12-31 23:59:59',1000,0],
      ['EDENEXPIRED',500,'2020-01-01 00:00:00',null,0],
      ['EDENUSED',500,null,1,1],
    ]) await insert('coupons', `INSERT IGNORE INTO coupons
      (code,discount_bps,expires_at,max_uses,uses,active) VALUES (?,?,?,?,?,1)`, row);
    await c.commit();
    return { inserted, placeholderServices: serviceSeeds.map(([id,title,category,priceCents]) => ({id,title,category,priceCents})) };
  } catch (error) {
    await c.rollback(); throw error;
  } finally { c.release(); }
}

if (process.argv[1]?.endsWith('seed-services.mjs')) {
  const uri = new URL(process.env.EDEN_MYSQL_URL);
  if (uri.hostname !== '127.0.0.1' || uri.pathname !== '/eden') throw new Error('This seed command is restricted to local 127.0.0.1/eden.');
  const db = mysql.createPool(process.env.EDEN_MYSQL_URL);
  try { console.log(JSON.stringify(await seedServices(db))); } finally { await db.end(); }
}

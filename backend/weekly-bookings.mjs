const week = 7 * 86400_000;
const lead = 24 * 3600_000;
const parse = value => typeof value === 'string' ? JSON.parse(value) : value;

export function nextWeeklyTime(original, now) {
  const first = Date.parse(original);
  if (!Number.isFinite(first)) return null;
  const occurrence = first + Math.max(1, Math.floor((now - first) / week) + 1) * week;
  return occurrence <= now + lead ? occurrence : null;
}

export async function runWeeklyBookings(db, now = Date.now()) {
  const [sources] = await db.query(`SELECT id FROM bookings
    WHERE status = 'completed' AND customer_id IS NOT NULL
    AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.recurring')) = 'true'
    AND COALESCE(JSON_UNQUOTE(JSON_EXTRACT(details, '$.paused')), 'false') <> 'true'`);
  for (const { id } of sources) {
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      const [[source]] = await connection.execute(`SELECT customer_id, details FROM bookings
        WHERE id = ? AND status = 'completed' FOR UPDATE`, [id]);
      if (source?.customer_id) {
        const original = parse(source.details);
        const scheduled = original.paused ? null : nextWeeklyTime(original.date, now);
        if (scheduled !== null) {
          const [[property]] = await connection.execute('SELECT id, details FROM properties WHERE id = ? AND owner = ?', [original.property.id, source.customer_id]);
          const [[service]] = await connection.execute('SELECT price_cents FROM services WHERE id = ? AND active = 1', [original.service]);
          if (property && service) {
            const reservation = await connection.execute('INSERT IGNORE INTO weekly_runs VALUES (?, ?)', [id, scheduled]);
            if (reservation[0].affectedRows === 1) {
              const snapshot = { ...parse(property.details), id: property.id };
              const cents = service.price_cents + (snapshot.size === 'Large' ? 1500 : 0);
              const details = {
                property: snapshot, service: original.service, date: new Date(scheduled).toISOString(),
                total: Math.round(cents * 1.13) / 100, notes: original.notes,
                recurring: false, messages: [], review: '',
              };
              await connection.execute('INSERT INTO bookings (customer_id, details) VALUES (?, ?)', [source.customer_id, JSON.stringify(details)]);
            }
          }
        }
      }
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  }
}

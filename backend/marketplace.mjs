import { Buffer } from 'node:buffer';
import { structuredAddress, propertyMeasurements } from './addresses.mjs';


const transitions = {
  accepted: 'enRoute', enRoute: 'arrived', arrived: 'working',
  working: 'submitted',
};
const customerNoticeStatuses = new Set(['accepted', 'enRoute', 'submitted']);

function error(status, message) {
  throw Object.assign(new Error(message), { status });
}

function text(value, max, required = false) {
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) {
    error(400, 'Check the submitted text.');
  }
  return value.trim();
}

export function image(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || value.length > 2_800_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    error(400, 'Choose an image under 2 MB.');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length > 2 * 1024 * 1024) error(400, 'Choose an image under 2 MB.');
  const header = bytes.toString('hex', 0, 8);
  const webp = header.startsWith('52494646') && bytes.toString('ascii', 8, 12) === 'WEBP';
  if (!header.startsWith('ffd8ff') && header !== '89504e470d0a1a0a' && !webp) {
    error(400, 'Choose a JPEG, PNG or WebP image.');
  }
  return value;
}

const parse = value => typeof value === 'string' ? JSON.parse(value) : value;
const property = row => ({ ...parse(row.details), id: row.id });
const primaryServiceIds = new Map([
  ['Snow removal', 'snow'],
  ['Lawn mowing', 'lawn'],
  ['House cleaning', 'cleaning'],
]);

function matchesOffer(details, user) {
  const sameCity = user.city_id != null && details.property?.cityId != null
    ? Number(user.city_id) === Number(details.property.cityId)
    : details.property?.address?.split(',')[1]?.trim().toLowerCase() === user.area?.trim().toLowerCase();
  const city = details.property?.address?.split(',')[1]?.trim().toLowerCase();
  return Boolean(sameCity && (details.property?.cityId != null || city) &&
    details.service === primaryServiceIds.get(user.service) &&
    !details.releasedBy?.includes(user.id));
}

function offerDetails(row) {
  const details = parse(row.details);
  if (row.status !== 'searching' || row.current_property == null) return details;
  return { ...details, property: { ...parse(row.current_property), id: details.property.id,
    ...(Object.hasOwn(row, 'current_city_id') ? { cityId: row.current_city_id } : {}) } };
}

const currentPropertyJoin = `LEFT JOIN properties p ON p.owner = b.customer_id
  AND p.id = JSON_UNQUOTE(JSON_EXTRACT(b.details, '$.property.id'))`;

const booking = row => {
  const { location, releasedBy, assignmentHistory, ...details } = parse(row.details);
  return { ...details, id: row.id, status: row.status, version: row.version };
};

async function bookingLocation(id, { method, user, run, first, read }) {
  const now = Date.now();
  if (method === 'GET' && user.role === 'customer') {
    const row = await first(`SELECT b.status, l.latitude, l.longitude, l.shared_at AS sharedAt
      FROM bookings b LEFT JOIN booking_locations l ON l.booking_id = b.id AND l.shared_at >= ?
      WHERE b.id = ? AND b.customer_id = ?`, now - 30_000, id, user.id);
    if (!row) error(404, 'Booking unavailable.');
    return { location: row.status === 'enRoute' && row.sharedAt != null
      ? { latitude: row.latitude, longitude: row.longitude, sharedAt: row.sharedAt } : null };
  }
  if (user.role === 'contractor' && method === 'DELETE') {
    await run(`DELETE l FROM booking_locations l JOIN bookings b ON b.id = l.booking_id
      WHERE b.id = ? AND b.contractor_id = ?`, id, user.id);
    return { stopped: true };
  }
  if (user.role === 'contractor' && method === 'POST') {
    const { latitude, longitude } = await read();
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180) error(400, 'Invalid location.');
    const result = await run(`INSERT INTO booking_locations (booking_id, latitude, longitude, shared_at)
      SELECT id, ?, ?, ? FROM bookings WHERE id = ? AND contractor_id = ? AND status = 'enRoute'
      ON DUPLICATE KEY UPDATE latitude = ?, longitude = ?, shared_at = ?`,
    latitude, longitude, now, id, user.id, latitude, longitude, now);
    if (!result.affectedRows) error(409, 'Location sharing is available for your assigned en-route bookings.');
    return { shared: true };
  }
  error(403, 'Location sharing is unavailable.');
}

export async function marketplace({ method, path, user, run, first, read, addressStore }) {
  if (path.startsWith('/api/properties')) {
    if (user.role !== 'customer') error(403, 'Switch to customer mode.');
    if (path === '/api/properties') {
      if (method === 'GET') {
        const records = (await run('SELECT * FROM properties WHERE owner = ? ORDER BY id', user.id)).map(row => ({
          ...property(row), ...(Object.hasOwn(row, 'city_id') ? { cityId: row.city_id } : {}),
        }));
        const selected = records.find(record => record.id === user.default_property) ?? records[0];
        return records.map(record => ({ ...record, isDefault: record.id === selected?.id }));
      }
      if (method === 'POST') {
        const body = await read();
        const id = body.id;
        if (id != null && (!Number.isInteger(id) || id <= 0)) error(400, 'Choose a valid property.');
        const existing = id == null ? null : await first('SELECT * FROM properties WHERE id = ? AND owner = ?', id, user.id);
        if (id != null && !existing) error(404, 'Property unavailable.');
        const previous = existing ? parse(existing.details) : {};
        if (body.structuredAddress != null && !addressStore) error(503, 'Structured addresses are awaiting the database update. Your existing address can still be saved.');
        const address = structuredAddress(body, previous.structuredAddress);
        const measurements = propertyMeasurements(body.measurements, previous.measurements);
        if (!['House', 'Apartment', 'Commercial'].includes(body.type)) error(400, 'Choose a property type.');
        let cityId = existing?.city_id ?? null;
        let pin = null;
        if (body.pin != null) {
          const { latitude, longitude } = body.pin;
          if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
              Math.abs(latitude) > 90 || Math.abs(longitude) > 180) error(400, 'Choose a valid map pin.');
          pin = { latitude, longitude };
        }
        const details = JSON.stringify({
          ...previous,
          name: text(body.name, 120, true),
          address: body.structuredAddress != null
            ? [address.street, address.city, address.state, address.postalCode, address.country].filter(Boolean).join(', ')
            : text(body.address, 250, true),
          size: text(body.size, 50, true), notes: text(body.notes, 1000),
          type: text(body.type, 50, true), photo: image(body.photo), pin,
          ...(address ? { structuredAddress: address } : {}),
          ...(measurements ? { measurements } : {}),
        });
        // Validate the complete property before creating a selected city record.
        if (body.structuredAddress != null) cityId = await addressStore.city({
          ...address,
          ...(body.addressSelection?.city === address.city && body.addressSelection?.country === address.country
            ? { latitude: body.addressSelection.latitude, longitude: body.addressSelection.longitude } : {}),
        });
        if (id == null) {
          const result = addressStore
            ? await run('INSERT INTO properties (owner, details, city_id) VALUES (?, ?, ?)', user.id, details, cityId)
            : await run('INSERT INTO properties (owner, details) VALUES (?, ?)', user.id, details);
          return { id: result.insertId };
        }
        const updated = addressStore
          ? await run('UPDATE properties SET details = ?, city_id = ? WHERE id = ? AND owner = ?', details, cityId, id, user.id)
          : await run('UPDATE properties SET details = ? WHERE id = ? AND owner = ?', details, id, user.id);
        if (!Number.isInteger(id) || !updated.affectedRows) {
          error(404, 'Property unavailable.');
        }
        return { id };
      }
    }
    const match = /^\/api\/properties\/(\d+)(\/default)?$/.exec(path);
    if (match) {
      const [, id, makeDefault] = match;
      if (makeDefault && method === 'POST') {
        const result = await run(`UPDATE users JOIN properties ON properties.owner = users.id
          SET users.default_property = properties.id WHERE users.id = ? AND properties.id = ?`, user.id, id);
        if (!result.affectedRows) error(404, 'Property unavailable.');
        return { id: Number(id) };
      }
      if (!makeDefault && method === 'DELETE') {
        await run('DELETE FROM properties WHERE id = ? AND owner = ?', id, user.id);
        return { deleted: true };
      }
    }
  }
  if (path === '/api/bookings') {
    if (method === 'GET') {
      if (user.role === 'customer') {
        return (await run('SELECT * FROM bookings WHERE customer_id = ? ORDER BY id DESC', user.id))
          .filter(row => !parse(row.details).customerDeleted).map(booking);
      }
      const records = await run(`SELECT b.*, p.details AS current_property${addressStore ? ', p.city_id AS current_city_id' : ''} FROM bookings b
        ${currentPropertyJoin} WHERE b.contractor_id = ? OR
        (b.status = 'searching' AND b.customer_id <> ? AND NOT EXISTS (SELECT 1 FROM preferences p WHERE p.user_id = ? AND JSON_UNQUOTE(JSON_EXTRACT(p.details, '$.available')) = 'false') AND NOT EXISTS (
          SELECT 1 FROM declined_jobs d WHERE d.booking_id = b.id AND d.contractor_id = ?))
        ORDER BY b.id DESC`, user.id, user.id, user.id, user.id);
      return records.filter(row => row.contractor_id === user.id ||
        matchesOffer(offerDetails(row), user)).map(row => {
        const job = booking({ ...row, details: offerDetails(row) });
        if (row.contractor_id !== user.id) {
          const location = job.property;
          job.property = { id: location.id, name: 'Service property', address: user.area,
            type: location.type, size: location.size, notes: '', photo: null, pin: null };
          job.notes = '';
          job.referencePhoto = null;
        }
        return job;
      });
    }
    if (method === 'POST') {
      if (user.role !== 'customer') error(403, 'Switch to customer mode.');
      const body = await read();
      const selected = await first('SELECT * FROM properties WHERE id = ? AND owner = ?', Number(body.propertyId) || 0, user.id);
      if (!selected) error(404, 'Property unavailable.');
      const date = typeof body.date === 'string' ? Date.parse(body.date) : NaN;
      const catalog = typeof body.service === 'string' && await first('SELECT price_cents FROM services WHERE id = ? AND active = 1', body.service);
      if (!Number.isFinite(date) || date <= Date.now() || date > Date.now() + 366 * 86400_000 || !catalog) {
        error(400, 'Choose a valid future date and an available service.');
      }
      const base = catalog.price_cents + (property(selected).size === 'Large' ? 1500 : 0) + (body.urgent === true ? 2000 : 0) +
        (body.walkway === true && body.service === 'snow' ? 1200 : 0);
      const total = Math.round(base * (body.discount === true ? 0.9 : 1) * 1.13) / 100;
      const details = {
        property: { ...property(selected), ...(addressStore ? { cityId: selected.city_id } : {}) }, service: body.service, date: new Date(date).toISOString(), total,
        notes: text(body.notes, 2000), recurring: body.recurring === true,
        referencePhoto: image(body.referencePhoto), review: '', messages: [],
      };
      const result = await run('INSERT INTO bookings (customer_id, details) VALUES (?, ?)', user.id, JSON.stringify(details));
      return { ...details, id: result.insertId, status: 'searching', version: 0 };
    }
  }
  const tracking = /^\/api\/bookings\/(\d+)\/location$/.exec(path);
  if (tracking) return bookingLocation(Number(tracking[1]), { method, user, run, first, read });
  const match = /^\/api\/bookings\/(\d+)$/.exec(path);
  if (method === 'POST' && match) {
    const id = Number(match[1]);
    const body = await read();
    const row = await first(`SELECT b.*, p.details AS current_property${addressStore ? ', p.city_id AS current_city_id' : ''} FROM bookings b
      ${currentPropertyJoin} WHERE b.id = ?`, id);
    if (!row) error(404, 'Booking unavailable.');
    const customer = user.role === 'customer' && row.customer_id === user.id;
    const assigned = user.role === 'contractor' && row.contractor_id === user.id;
    const available = user.role === 'contractor' && !await first("SELECT 1 FROM preferences WHERE user_id = ? AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.available')) = 'false'", user.id);
    const details = offerDetails(row);
    const offered = available && row.customer_id && row.customer_id !== user.id &&
      row.status === 'searching' && matchesOffer(details, user);
    let status = row.status;
    let contractor = row.contractor_id;
    if (offered && body.action === 'decline') {
      await run('INSERT IGNORE INTO declined_jobs (booking_id, contractor_id) VALUES (?, ?)', id, user.id);
      return { declined: true };
    }
    if (offered && body.action === 'accept') {
      const verification = await first('SELECT status FROM contractor_reviews WHERE user_id = ?', user.id);
      if (verification?.status !== 'Approved') error(403, 'Contractor verification is required before accepting jobs.');
      if (await first('SELECT 1 FROM declined_jobs WHERE booking_id = ? AND contractor_id = ?', id, user.id)) {
        error(409, 'You already declined this offer.');
      }
      contractor = user.id;
      status = 'accepted';
    } else {
      if (!customer && !assigned) error(404, 'Booking unavailable.');
      if (status === 'cancelled') error(409, 'This booking was cancelled.');
      switch (body.action) {
        case 'delete':
          if (!customer || status !== 'searching' || contractor != null) error(409, 'Only unaccepted bookings can be deleted.');
          details.customerDeleted = true;
          details.paused = true;
          status = 'cancelled';
          break;
        case 'edit': {
          if (!customer || status !== 'searching' || contractor != null) error(409, 'Only unaccepted bookings can be edited.');
          const date = typeof body.date === 'string' ? Date.parse(body.date) : NaN;
          if (!Number.isFinite(date) || date <= Date.now() || date > Date.now() + 366 * 86400_000) error(400, 'Choose a valid future date.');
          details.date = new Date(date).toISOString();
          details.notes = text(body.notes, 2000);
          break;
        }
        case 'cancel':
          if (!assigned || !['enRoute', 'arrived', 'working', 'submitted'].includes(status)) error(409, 'Cancellation is available after departure. Use Release job before departure.');
          details.assignmentHistory = [...(details.assignmentHistory ?? []), {
            contractorId: user.id, status, at: new Date().toISOString(),
            before: details.before ?? null, after: details.after ?? null,
            messages: details.messages ?? [], chatRead: details.chatRead ?? {},
          }];
          details.releasedBy = [...new Set([...(details.releasedBy ?? []), user.id])];
          details.messages = [];
          details.chatRead = {};
          details.before = null;
          details.after = null;
          status = 'searching';
          contractor = null;
          break;
        case 'release':
          if (!assigned || status !== 'accepted') error(409, 'Only accepted jobs can be released before departure.');
          status = 'searching';
          contractor = null;
          details.releasedBy = [...(details.releasedBy ?? []), user.id];
          details.messages = [];
          details.chatRead = {};
          break;
        case 'advance':
          if (assigned && typeof body.status === 'string' && transitions[status] === body.status &&
              (status !== 'arrived' || details.before) && (status !== 'working' || details.after)) {
            status = body.status;

          } else if (customer && status === 'submitted' && body.status === 'completed') {
            status = 'completed';
          } else error(409, 'This booking cannot move to that status.');
          break;
        case 'rework':
          if (!customer || status !== 'submitted') error(409, 'Rework is unavailable.');
          status = 'working';
          details.after = null;
          details.messages.push({ contractor: false, text: 'I requested rework.', image: null });
          break;
        case 'before':
        case 'after':
          if (!assigned || status !== (body.action === 'before' ? 'arrived' : 'working')) error(409, 'Work photos are unavailable at this stage.');
          details[body.action] = image(body.image);
          break;

        case 'weekly':
          if (!customer || !details.recurring || typeof body.paused !== 'boolean') error(400, 'Invalid weekly preference.');
          details.paused = body.paused;
          break;
        case 'review':
          if (!customer || status !== 'completed' || details.rating || !Number.isInteger(body.rating) ||
              body.rating < 1 || body.rating > 5) error(409, 'Review unavailable.');
          details.rating = body.rating;
          details.review = text(body.review, 2000);
          break;
        case 'message': {
          if (!row.contractor_id || status === 'cancelled') error(409, 'Chat is available for assigned bookings.');
          const message = { contractor: assigned, text: text(body.text, 2000), image: image(body.image) };
          if (!message.text && !message.image) error(400, 'Enter a message or attach an image.');
          if (details.messages.length >= 100 || JSON.stringify(details.messages).length + (message.image?.length || 0) > 4_000_000) {
            error(409, 'This conversation has reached its storage limit.');
          }
          details.messages.push(message);
          break;
        }
        case 'read': {
          const count = body.count;
          if (!row.contractor_id || !Number.isInteger(count) || count < 0 ||
              count > details.messages.length) error(400, 'Invalid conversation position.');
          const role = customer ? 'customer' : 'contractor';
          const previous = details.chatRead?.[role] ?? 0;
          if (count <= previous) return booking(row);
          details.chatRead = { ...details.chatRead, [role]: count };
          break;
        }
        default:
          error(400, 'Choose a valid booking action.');
      }
    }
    if (status !== row.status && customerNoticeStatuses.has(status)) {
      details.customerNotices = [
        ...(details.customerNotices ?? []).slice(-49),
        { status, version: row.version + 1, at: new Date().toISOString() },
      ];
    }
    const result = await run(`UPDATE bookings SET details = ?, status = ?, contractor_id = ?, version = version + 1
      WHERE id = ? AND version = ?`, JSON.stringify(details), status, contractor, id, row.version);
    if (!result.affectedRows) error(409, 'The booking changed. Refresh and try again.');
    return booking({ id, status, version: row.version + 1, details });
  }
  return undefined;
}

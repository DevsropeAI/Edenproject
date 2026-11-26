import {browserMapConfig} from './browser-map-config.mjs';
import {validateWorkPin,saveWorkPin} from './work-pin.mjs';
import {assignLongTerm} from './long-term-dispatch.mjs';
import { image, marketplace } from './marketplace.mjs';
import { createGeocoding } from './geocoding.mjs';
import { createAddressStore } from './addresses.mjs';
import { createPricing } from './pricing.mjs';
import { catalogAdmin, contractorServices } from './catalog-routes.mjs';
import { mapData, markerConfig } from './map-data.mjs';
import { createServer } from 'node:http';
import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

const roles = new Set(['customer', 'contractor']);
const services = ['Snow removal', 'Lawn mowing', 'House cleaning'];

function fail(status, message) {
  throw Object.assign(new Error(message), { status });
}

function field(body, key, max, required = true) {
  const value = typeof body[key] === 'string' ? body[key].trim() : '';
  if ((required && !value) || value.length > max) fail(400, 'Invalid ' + key + '.');
  return value;
}

function credentials(body, registering = false) {
  const email = field(body, 'email', 254).toLowerCase();
  const password = body.password;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || typeof password !== 'string' ||
      password.length < (registering ? 8 : 1) || password.length > 256) {
    fail(400, 'Enter a valid email address and password.');
  }
  return { email, password };
}

function contractorDetails(body, allowedServices = services) {
  const area = field(body, 'area', 150);
  const service = field(body, 'service', 80);
  if (!allowedServices.some(value => value.toLowerCase() === service.toLowerCase())) fail(400, 'Choose a supported primary service.');
  return { area, service };
}

function hashPassword(password, salt = randomBytes(16).toString('hex')) {
  return salt + ':' + scryptSync(password, salt, 64).toString('hex');
}

function verifyPassword(password, stored) {
  const salt = stored.split(':')[0];
  return timingSafeEqual(Buffer.from(hashPassword(password, salt)), Buffer.from(stored));
}

const digest = value => createHash('sha256').update(value).digest('hex');
const token = () => randomBytes(32).toString('hex');
const dummyHash = hashPassword('unused');

async function readJson(req, limit = 16384) {
  let length = 0;
  const chunks = [];
  for await (const chunk of req) {
    length += chunk.length;
    if (length > limit) fail(413, 'Request is too large.');
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString());
    if (body && typeof body === 'object' && !Array.isArray(body)) return body;
  } catch {}
  fail(400, 'Send a JSON object.');
}

export function createApi({
  db,
  origins = [],
  adminKey,
  sendPasswordReset,
  phoneVerification,
  payments,
  structuredAddresses = false,
  servicesPricing = false,
  largeJobsDispatch = false,
  walking,
  geocoding = createGeocoding(),
} = {}) {
  const run = async (sql, ...args) => (await db.execute(sql, args))[0];
  const first = async (sql, ...args) => (await run(sql, ...args))[0];
  const addressStore = structuredAddresses ? createAddressStore(run, first) : null;
  const pricing = servicesPricing ? createPricing(db) : null;
  const userById = id => first('SELECT * FROM users WHERE id = ?', id);
  const publicUser = ({ id, email, name, phone, role, customer, contractor, area, service, city_id }) => ({
    id, email, name, phone, role, area, service, cityId: city_id ?? null,
    roles: [...(customer ? ['customer'] : []), ...(contractor ? ['contractor'] : [])],
  });
  const attempts = new Map();

  function limitAuth(req, scope = 'auth') {
    const ip = scope + ':' + req.socket.remoteAddress;
    const now = Date.now();
    for (const [address, attempt] of attempts) {
      if (attempt.until <= now) attempts.delete(address);
    }
    const attempt = attempts.get(ip) ?? { count: 0, until: now + 60_000 };
    attempts.set(ip, attempt);
    if (++attempt.count > 25) fail(429, 'Try again in a minute.');
  }

  async function route(req, path) {
    const method = req.method;
    if (method === 'POST' && path === '/api/payments/webhook' && payments) return payments.webhook(req, run, first);
    if (method === 'GET' && path === '/api/health') return { status: 'ok' };
    if (method === 'GET' && path === '/api/map-config') return markerConfig;
    if (method === 'GET' && path === '/api/services') {
      if (pricing) return run(`SELECT id,title,price_cents AS priceCents,service_category,
        short_description AS description,image_url AS imageUrl,estimated_duration_minutes AS durationMinutes,
        minimum_price_cents AS minimumPriceCents,currency FROM services WHERE active=1 ORDER BY title`);
      return run('SELECT id, title, price_cents AS priceCents FROM services WHERE active = 1 ORDER BY id');
    }
    if (method === 'POST' && path === '/api/auth/password-reset/request') {
      limitAuth(req);
      if (!sendPasswordReset) fail(503, 'Password reset email is unavailable.');
      const email = field(await readJson(req), 'email', 254).toLowerCase();
      const account = await first('SELECT id FROM users WHERE email = ? AND blocked = 0', email);
      if (account) {
        const code = token();
        await run('DELETE FROM password_resets WHERE user_id = ? OR expires <= ?', account.id, Date.now());
        await run('INSERT INTO password_resets VALUES (?, ?, ?)', digest(code), account.id, Date.now() + 20 * 60_000);
        await sendPasswordReset(email, code);
      }
      return { accepted: true };
    }
    if (method === 'POST' && path === '/api/auth/password-reset/confirm') {
      limitAuth(req);
      const body = await readJson(req);
      const code = field(body, 'code', 64);
      if (!/^[a-f0-9]{64}$/.test(code) || typeof body.password !== 'string' || body.password.length < 8 || body.password.length > 256) {
        fail(400, 'Enter a valid reset code and new password.');
      }
      const password = hashPassword(body.password);
      const connection = await db.getConnection();
      try {
        await connection.beginTransaction();
        const [[reset]] = await connection.execute('SELECT user_id FROM password_resets WHERE token = ? AND expires > ? FOR UPDATE', [digest(code), Date.now()]);
        if (!reset) fail(400, 'The reset code expired or was already used.');
        await connection.execute('UPDATE users SET password = ? WHERE id = ?', [password, reset.user_id]);
        await connection.execute('DELETE FROM sessions WHERE user_id = ?', [reset.user_id]);
        await connection.execute('DELETE FROM password_resets WHERE user_id = ?', [reset.user_id]);
        await connection.commit();
      } catch (error) {
        await connection.rollback();
        throw error;
      } finally {
        connection.release();
      }
      return { changed: true };
    }
    if (method === 'GET' && path === '/api/auth/options') {
      return { phoneVerification: Boolean(phoneVerification), contractorOfferDetails: true, contractorRegistrationServices: Boolean(pricing), contractorWorkPin: true };
    }
    if (method === 'GET' && path === '/api/auth/work-city-options') {
      limitAuth(req, 'city');
      return geocoding.capabilities;
    }
    if (method === 'GET' && ['/api/auth/work-city-search', '/api/auth/work-city-autocomplete', '/api/auth/work-city-place'].includes(path)) {
      limitAuth(req, 'city');
      const params = new URL(req.url, 'http://localhost').searchParams;
      params.set('type', 'city');
      return geocoding.lookup(
        path.endsWith('autocomplete') ? 'autocomplete' : path.endsWith('place') ? 'place' : 'search',
        params, 'registration:' + digest(req.socket.remoteAddress ?? 'unknown'),
      );
    }
    if (method === 'POST' && path === '/api/auth/phone-verification') {
      limitAuth(req);
      if (!phoneVerification) fail(503, 'SMS verification is unavailable.');
      const phone = field(await readJson(req), 'phone', 35);
      if (!/^\+[1-9]\d{7,14}$/.test(phone)) fail(400, 'Enter a phone number with its country code.');
      await phoneVerification.send(phone);
      return { sent: true };
    }
    if (method === 'POST' && path === '/api/auth/register') {
      limitAuth(req);
      const body = await readJson(req);
      const { email, password } = credentials(body, true);
      const { role } = body;
      if (!roles.has(role)) fail(400, 'Choose an account role.');
      if(body.workPin!=null&&role!=='contractor')fail(400,'Work-location pins are for contractor accounts.');
      const workPin=body.workPin==null?null:validateWorkPin(body.workPin);
      const name = field(body, 'name', 100);
      const phone = field(body, 'phone', 35);
      if (phone.replace(/\D/g, '').length < 7) fail(400, 'Enter a valid phone number.');
      const catalog = role === 'contractor' && pricing ? await run('SELECT id, title FROM services WHERE active = 1 ORDER BY title') : null;
      const { area, service } = role === 'contractor' ? contractorDetails(workPin?{...body,area:typeof body.area==='string'&&body.area.trim()?body.area:'Pinned work location'}:body, catalog?.map(row => row.title) ?? services) : { area: '', service: '' };
      const serviceIds = body.serviceIds ?? [];
      if (!Array.isArray(serviceIds) || serviceIds.length > 50 || serviceIds.some(id => typeof id !== 'string' || !id.length || id.length > 20) || new Set(serviceIds).size !== serviceIds.length) fail(400, 'Choose valid additional services.');
      if (serviceIds.length && role !== 'contractor') fail(400, 'Additional services are for contractor accounts.');
      if (serviceIds.length && !pricing) fail(503, 'Additional services are awaiting the services database update.');
      if (serviceIds.some(id => !catalog?.some(row => row.id === id))) fail(400, 'A selected service is unavailable.');
      if (body.workCity != null && role !== 'contractor') fail(400, 'Work city is for contractor accounts.');
      if (body.workCity != null && !addressStore) fail(503, 'City selection is awaiting the database update. Enter the service area manually.');
      if (phoneVerification) {
        const code = field(body, 'phoneCode', 10);
        if (!/^\+[1-9]\d{7,14}$/.test(phone) || !/^\d{4,10}$/.test(code) || !await phoneVerification.check(phone, code)) {
          fail(400, 'Enter a valid SMS verification code.');
        }
      }
      try {
        if (body.workCity != null || serviceIds.length || workPin) {
          const connection = await db.getConnection();
          try {
            await connection.beginTransaction();
            const transactionRun = async (sql, ...args) => (await connection.execute(sql, args))[0];
            const transactionFirst = async (sql, ...args) => (await transactionRun(sql, ...args))[0];
            const cityId = body.workCity != null ? await createAddressStore(transactionRun, transactionFirst).city(body.workCity) : null;
            for (const id of [...serviceIds].sort()) {
              if (!await transactionFirst('SELECT id FROM services WHERE id = ? AND active = 1 FOR UPDATE', id)) fail(400, 'A selected service is unavailable.');
            }
            const userId = token();
            if (body.workCity != null) await transactionRun(`
              INSERT INTO users (id, email, password, name, phone, role, customer, contractor, area, service, city_id)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, userId, email, hashPassword(password), name, phone, role,
            Number(role === 'customer'), Number(role === 'contractor'), area, service, cityId);
            else await transactionRun(`
              INSERT INTO users (id, email, password, name, phone, role, customer, contractor, area, service)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, userId, email, hashPassword(password), name, phone, role, Number(role === 'customer'), Number(role === 'contractor'), area, service);
            for (const id of serviceIds) await transactionRun('INSERT INTO contractor_services (user_id, service_id) VALUES (?, ?)', userId, id);
            if(workPin)await saveWorkPin(transactionRun,userId,workPin);
            await connection.commit();
          } catch (error) {
            await connection.rollback();
            throw error;
          } finally {
            connection.release();
          }
        } else await run(`
          INSERT INTO users (id, email, password, name, phone, role, customer, contractor, area, service)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, token(), email, hashPassword(password), name, phone, role, Number(role === 'customer'), Number(role === 'contractor'), area, service);
      } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') fail(409, 'An account already uses this email.');
        throw error;
      }
      return { registered: true };
    }
    if (method === 'POST' && path === '/api/auth/login') {
      limitAuth(req);
      const { email, password } = credentials(await readJson(req));
      const user = await first('SELECT * FROM users WHERE email = ?', email);
      if (!verifyPassword(password, user?.password ?? dummyHash) || !user) fail(401, 'Incorrect email or password.');
      if (user.blocked) fail(403, 'This account is blocked.');
      const session = token();
      await run('DELETE FROM sessions WHERE expires <= ?', Date.now());
      await run('INSERT INTO sessions VALUES (?, ?, ?)', digest(session), user.id, Date.now() + 30 * 86400_000);
      return { token: session, user: publicUser(user) };
    }

    const authorization = req.headers.authorization ?? '';
    if (path.startsWith('/api/admin/')) {
      if (!adminKey || !timingSafeEqual(Buffer.from(digest(authorization)), Buffer.from(digest('Bearer ' + adminKey)))) {
        fail(401, 'Admin authentication required.');
      }
      if(walking&&(path.startsWith('/api/admin/walking/')||path.endsWith('/door-to-door'))){
        const result=await walking.route({method,path,admin:true,body:method==='POST'?await readJson(req):{},params:new URL(req.url,'http://localhost').searchParams});
        if(result!==undefined)return result;
      }
      if(method==='GET'&&path==='/api/admin/map') return {...await mapData(run,{role:'admin'}),browserMapConfig:browserMapConfig()};
      if (pricing) {
        const response=await catalogAdmin({path,method,read:()=>readJson(req),run,db});
        if(response!==undefined)return response;
      }
      if (method === 'GET' && path === '/api/admin/dashboard') {
        const accounts = await run('SELECT * FROM users ORDER BY name');
        const record = user => ({ id: user.id, title: user.name, detail: user.email, status: user.blocked ? 'Blocked' : 'Active' });
        const contractorRows = largeJobsDispatch ? await run(`
          SELECT users.*, services.id AS primaryServiceId,
            COALESCE(contractor_reviews.status, 'Pending') AS verificationStatus
          FROM users
          LEFT JOIN services ON LOWER(services.title) = LOWER(users.service)
          LEFT JOIN contractor_reviews ON contractor_reviews.user_id = users.id
          WHERE users.contractor = 1 ORDER BY users.name
        `) : accounts.filter(user => user.contractor);
        const additionalServiceRows = largeJobsDispatch
          ? await run('SELECT user_id, service_id FROM contractor_services')
          : [];
        const additionalServices = new Map();
        for (const row of additionalServiceRows) {
          const serviceIds = additionalServices.get(row.user_id) ?? [];
          serviceIds.push(row.service_id);
          additionalServices.set(row.user_id, serviceIds);
        }
        const contractors = contractorRows.map(user => ({
          ...record(user),
          doorToDoorEnabled: Boolean(user.door_to_door_enabled),
          area: user.area ?? '',
          cityId: user.city_id ?? null,
          verificationStatus: user.verificationStatus ?? 'Pending',
          serviceIds: [...new Set([
            user.primaryServiceId,
            ...(additionalServices.get(user.id) ?? []),
          ].filter(Boolean))],
        }));
        return {
          Map: [],
          Orders: (await run(`SELECT id, status,
            JSON_UNQUOTE(JSON_EXTRACT(details, '$.service')) AS service,
            JSON_UNQUOTE(JSON_EXTRACT(details, '$.total')) AS total
            FROM bookings ORDER BY id DESC`)).map(row => ({
              id: String(row.id), title: 'Booking #' + row.id,
              detail: row.service + ' · CAD ' + row.total, status: row.status,
            })),
          Customers: accounts.filter(user => user.customer).map(record),
          Contractors: contractors,
          Payments: payments ? await payments.adminList(run) : [],
          Services: (await run('SELECT * FROM services ORDER BY id')).map(service => ({
            id: service.id, title: service.title, detail: 'CAD ' + (service.price_cents / 100).toFixed(2),
            description: service.short_description ?? '', imageUrl: service.image_url ?? '', durationMinutes: service.estimated_duration_minutes ?? 60, minimumPriceCents: service.minimum_price_cents ?? 0, priceCents: service.price_cents, service_category: service.service_category ?? 'small', status: service.active ? 'Active' : 'Inactive',
          })),
          Verification: await run(`SELECT users.id, users.name AS title, users.email AS detail,
            COALESCE(contractor_reviews.status, 'Pending') AS status, COUNT(account_images.kind) = 2 AS complete
            FROM users JOIN account_images ON account_images.user_id = users.id AND account_images.kind <> 'profile'
            LEFT JOIN contractor_reviews ON contractor_reviews.user_id = users.id
            WHERE users.contractor = 1 GROUP BY users.id, users.name, users.email, contractor_reviews.status`),
          LargeJobs: [], // Deprecated compatibility key; service categories no longer control dispatch.
          LongTermJobs: pricing ? (await run(`SELECT b.*, u.name AS customer_name, u.email AS customer_email
            FROM bookings b LEFT JOIN users u ON u.id=b.customer_id
            WHERE b.status='searching' AND b.dispatch_status='pending_admin'
            AND JSON_UNQUOTE(JSON_EXTRACT(b.details, '$.bookingType'))='long_term' ORDER BY b.id DESC`)).map(row=>{
              const d=typeof row.details==='string'?JSON.parse(row.details):row.details;
              return {id:String(row.id),title:(d.serviceTitle??d.service)+' #'+row.id,
                detail:[row.customer_name,row.customer_email].filter(Boolean).join(' · '),
                address:d.property?.address??'',notes:d.notes??'',propertyNotes:d.property?.notes??'',measurements:d.property?.measurements??{},
                scheduledDate:d.scheduledDate??d.date,total:d.total,status:row.dispatch_status};
            }) : [],
          Support: await run(`SELECT support.id, support.description AS title, users.email AS detail, support.status
            FROM support JOIN users ON users.id = support.user_id ORDER BY support.created_at DESC, support.id DESC`),
        };
      }
      const refund = /^\/api\/admin\/payments\/([a-f0-9-]{36})$/.exec(path);
      if (method === 'POST' && refund && payments) {
        const { status } = await readJson(req);
        return payments.reviewRefund(refund[1], status, run, first);
      }
      const service = /^\/api\/admin\/services\/(snow|lawn|cleaning)$/.exec(path);
      if (method === 'POST' && service) {
        const { status, priceCents } = await readJson(req);
        if (!['Active', 'Inactive'].includes(status) || !Number.isInteger(priceCents) || priceCents < 100 || priceCents > 1000000) {
          fail(400, 'Enter a valid service price and status.');
        }
        await run('UPDATE services SET active = ?, price_cents = ? WHERE id = ?', Number(status === 'Active'), priceCents, service[1]);
        return { status };
      }
      const verification = /^\/api\/admin\/verification\/([a-f0-9]{64})(?:\/(identification|insurance))?$/.exec(path);
      if (verification) {
        const [, id, kind] = verification;
        if (method === 'GET' && kind) {
          const document = await first('SELECT data FROM account_images WHERE user_id = ? AND kind = ?', id, kind);
          if (!document) fail(404, 'Document unavailable.');
          return { image: document.data };
        }
        if (method === 'POST' && !kind) {
          const { status } = await readJson(req);
          if (!['Approved', 'Rejected'].includes(status)) fail(400, 'Choose a review decision.');
          const result = await run(`INSERT INTO contractor_reviews (user_id, status)
            SELECT users.id, ? FROM users JOIN account_images ON account_images.user_id = users.id
            WHERE users.id = ? AND users.contractor = 1 AND account_images.kind IN ('identification', 'insurance')
            GROUP BY users.id HAVING COUNT(*) = 2
            ON DUPLICATE KEY UPDATE status = ?`, status, id, status);
          if (!result.affectedRows) fail(409, 'Both documents are required.');
          return { status };
        }
      }
      const order = /^\/api\/admin\/orders\/(\d+)$/.exec(path);
      if (method === 'POST' && order) {
        const { status } = await readJson(req);
        if (status !== 'cancelled') fail(400, 'Choose a valid order action.');
        const result = await run(`UPDATE bookings SET status = 'cancelled', version = version + 1
          WHERE id = ? AND status NOT IN ('completed', 'cancelled')`, order[1]);
        if (!result.affectedRows) fail(409, 'This booking cannot be cancelled.');
        return { status };
      }
      const dispatch = /^\/api\/admin\/dispatch\/(\d+)$/.exec(path);
      if (method === 'POST' && dispatch && pricing) return assignLongTerm(db,Number(dispatch[1]),await readJson(req));
      const match = /^\/api\/admin\/(accounts|support)\/([a-f0-9]{64})$/.exec(path);
      if (method === 'POST' && match) {
        const { status } = await readJson(req);
        const [, type, id] = match;
        const allowed = type === 'accounts' ? ['Active', 'Blocked'] : ['Open', 'In review', 'Resolved'];
        if (!allowed.includes(status)) fail(400, 'Invalid status.');
        const result = type === 'accounts'
          ? await run('UPDATE users SET blocked = ? WHERE id = ?', Number(status === 'Blocked'), id)
          : await run('UPDATE support SET status = ? WHERE id = ?', status, id);
        if (!result.affectedRows) fail(404, 'Record not found.');
        if (type === 'accounts' && status === 'Blocked') await run('DELETE FROM sessions WHERE user_id = ?', id);
        return { status };
      }
      fail(404, 'Endpoint not found.');
    }

    const session = digest(authorization.startsWith('Bearer ') ? authorization.slice(7) : '');
    const user = await first(`
      SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id
      WHERE sessions.token = ? AND sessions.expires > ? AND users.blocked = 0
    `, session, Date.now());
    if (!user) fail(401, 'Sign in to continue.');
    if(walking&&path.startsWith('/api/walking/'))return walking.route({method,path,user,body:method==='POST'?await readJson(req,100000):{}});
    if(pricing&&method==='GET'&&path==='/api/contractor/map') {
      const offers=await marketplace({method:'GET',path:'/api/bookings',user,run,first,addressStore,pricing});
      return mapData(run,user,offers);
    }
    if (pricing && path==='/api/contractor/services') return contractorServices({method,user,read:()=>readJson(req),run,db});
    if (pricing && path==='/api/quotes' && method==='POST') return pricing.quote(user,await readJson(req));
    if (pricing && path==='/api/add-ons' && method==='GET') {
      if(user.role!=='customer')fail(403,'Switch to customer mode.');
      return run('SELECT id,service_id,name,price_cents FROM add_ons WHERE active=1 ORDER BY name');
    }

    if (path.startsWith('/api/geo/')) {
      if (!roles.has(user.role)) fail(403, 'Choose a customer or contractor account.');
      if (method !== 'GET') fail(405, 'Use a GET request.');
      if (path === '/api/geo/capabilities') return {
        ...geocoding.capabilities, structuredAddresses,
      };
      const kind = path.slice('/api/geo/'.length);
      if (!['search', 'autocomplete', 'reverse', 'place'].includes(kind)) fail(404, 'Endpoint not found.');
      return geocoding.lookup(kind, new URL(req.url, 'http://localhost').searchParams, user.id);
    }
    if (method === 'GET' && path === '/api/contractor/work-location') {
      if (user.role !== 'contractor') fail(403, 'Switch to contractor mode.');
      const city = addressStore && user.city_id
        ? await first('SELECT id, name, state, country, latitude, longitude FROM cities WHERE id = ?', user.city_id)
        : null;
      const preference=await first('SELECT details FROM preferences WHERE user_id = ?',user.id);
      const preferences=typeof preference?.details==='string'?JSON.parse(preference.details):preference?.details??{};
      return { area: user.area, city, workPin: preferences.workPin??null };
    }
    if (method === 'POST' && path === '/api/contractor/work-location') {
      if (user.role !== 'contractor') fail(403, 'Switch to contractor mode.');
      const body = await readJson(req);
      if(body.workPin!=null){const pin=validateWorkPin(body.workPin);await saveWorkPin(run,user.id,pin);return {saved:true,workPin:pin};}
      if (!addressStore) fail(503, 'Structured work locations are awaiting the database update. Your existing service area still works.');
      if (body.city == null) fail(400, 'Select a city or work-location pin.');
      const cityId = await addressStore.city(body.city);
      await run('UPDATE users SET city_id = ? WHERE id = ?', cityId, user.id);
      return { saved: true, cityId };
    }
    if (path === '/api/payments' && method === 'GET') {
      return { enabled: Boolean(payments), records: payments ? await payments.list(user, run) : [] };
    }
    const payment = /^\/api\/payments\/(\d+)$/.exec(path);
    if (method === 'POST' && payment) {
      if (!payments) fail(503, 'Online payments are unavailable.');
      return payments.customerAction(user, Number(payment[1]), await readJson(req), run, first);
    }
    if (method === 'GET' && path === '/api/auth/me') return publicUser(user);
    if (method === 'POST' && path === '/api/auth/logout') {
      await run('DELETE FROM sessions WHERE token = ?', session);
      return { signedOut: true };
    }
    if (method === 'POST' && path === '/api/auth/mode') {
      const body = await readJson(req);
      const { role } = body;
      if (!roles.has(role)) fail(400, 'Choose an account role.');
      if (role === 'contractor' && !user.contractor) {
        const activeServices = pricing ? await run('SELECT title FROM services WHERE active=1') : null;
        const { area, service } = contractorDetails(body, activeServices?.map(row=>row.title) ?? services);
        await run("UPDATE users SET contractor = 1, role = 'contractor', area = ?, service = ? WHERE id = ?", area, service, user.id);
      } else if (role === 'customer') {
        await run("UPDATE users SET customer = 1, role = 'customer' WHERE id = ?", user.id);
      } else {
        await run("UPDATE users SET role = 'contractor' WHERE id = ?", user.id);
      }
      return publicUser(await userById(user.id));
    }
    if (method === 'POST' && path === '/api/auth/profile') {
      const body = await readJson(req);
      const name = field(body, 'name', 100);
      const phone = field(body, 'phone', 35, false);
      if (phone && phone.replace(/\D/g, '').length < 7) fail(400, 'Enter a valid phone number.');
      await run('UPDATE users SET name = ?, phone = ? WHERE id = ?', name, phone, user.id);
      return publicUser(await userById(user.id));
    }
    if (method === 'DELETE' && path === '/api/auth/me') {
      const connection = await db.getConnection();
      try {
        await connection.beginTransaction();
        await connection.execute('DELETE FROM bookings WHERE customer_id = ?', [user.id]);
        await connection.execute(`UPDATE bookings SET status = 'cancelled', version = version + 1
          WHERE contractor_id = ? AND status NOT IN ('completed', 'cancelled')`, [user.id]);
        await connection.execute('DELETE FROM users WHERE id = ?', [user.id]);
        await connection.commit();
      } catch (error) {
        await connection.rollback();
        throw error;
      } finally {
        connection.release();
      }
      return { deleted: true };
    }
    if (path === '/api/support' && method === 'POST') {
      const description = field(await readJson(req), 'description', 1000);
      await run('INSERT INTO support (id, user_id, description) VALUES (?, ?, ?)', token(), user.id, description);
      return { submitted: true };
    }
    if (path === '/api/support' && method === 'GET') {
      return await run('SELECT id, description, status FROM support WHERE user_id = ? ORDER BY created_at DESC, id DESC', user.id);
    }
    if (method === 'GET' && path === '/api/contractor/verification') {
      if (user.role !== 'contractor') fail(403, 'Switch to contractor mode.');
      const review = await first('SELECT status FROM contractor_reviews WHERE user_id = ?', user.id);
      const documents = await run(
        "SELECT kind FROM account_images WHERE user_id = ? AND kind IN ('identification', 'insurance')", user.id,
      );
      return { status: review?.status ?? (documents.length === 2 ? 'Pending' : 'Incomplete') };
    }
    const photo = /^\/api\/account-images\/(profile|identification|insurance)$/.exec(path);
    if (photo) {
      const kind = photo[1];
      if (kind !== 'profile' && user.role !== 'contractor') fail(403, 'Switch to contractor mode.');
      if (method === 'GET') {
        const saved = await first('SELECT data FROM account_images WHERE user_id = ? AND kind = ?', user.id, kind);
        return { image: saved?.data ?? null };
      }
      if (method === 'POST') {
        const data = image((await readJson(req, 3_000_000)).image);
        if (data == null) {
          await run('DELETE FROM account_images WHERE user_id = ? AND kind = ?', user.id, kind);
        } else {
          await run(`INSERT INTO account_images (user_id, kind, data) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE data = ?`, user.id, kind, data, data);
        }
        if (kind !== 'profile') await run('DELETE FROM contractor_reviews WHERE user_id = ?', user.id);
        return { saved: true };
      }
    }
    if (path === '/api/preferences') {
      if (method === 'GET') {
        const saved = await first('SELECT details FROM preferences WHERE user_id = ?', user.id);
        return typeof saved?.details === 'string' ? JSON.parse(saved.details) : saved?.details ?? {};
      }
      if (method === 'POST') {
        const body = await readJson(req);
        const allowed = {
          notifications: value => typeof value === 'boolean',
          available: value => typeof value === 'boolean' && user.role === 'contractor',
          snowProperty: value => user.role === 'customer' && (value === null || Number.isInteger(value)),
          threshold: value => user.role === 'customer' && [1, 2, 3, 4, 6].includes(value),
          opens: value => user.role === 'contractor' && Number.isInteger(value) && value >= 0 && value < 1440,
          closes: value => user.role === 'contractor' && Number.isInteger(value) && value >= 0 && value < 1440,
          radius: value => user.role === 'contractor' && Number.isInteger(value) && value >= 1 && value <= 100,
        };
        if (!Object.keys(body).length || Object.entries(body).some(([key, value]) => !Object.hasOwn(allowed, key) || !allowed[key](value))) {
          fail(400, 'Invalid preference.');
        }
        if (body.snowProperty != null && !await first('SELECT id FROM properties WHERE id = ? AND owner = ?', body.snowProperty, user.id)) {
          fail(404, 'Property unavailable.');
        }
        const details = JSON.stringify(body);
        await run(`INSERT INTO preferences (user_id, details) VALUES (?, ?)
          ON DUPLICATE KEY UPDATE details = JSON_MERGE_PATCH(details, ?)`, user.id, details, details);
        return { saved: true };
      }
    }
    const result = await marketplace({ method, path, user, run, first, addressStore, pricing, read: () => readJson(req, 3_000_000) });
    if (result !== undefined) return result;
    fail(404, 'Endpoint not found.');
  }

  const server = createServer(async (req, res) => {
    const origin = req.headers.origin;
    res.setHeader('Vary', 'Origin');
    res.setHeader('Cache-Control', 'no-store');
    if (origin && (origins.includes(origin) || origins.includes('*'))) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    }
    if (req.method === 'OPTIONS') {
      res.writeHead(204).end();
      return;
    }
    try {
      const result = await route(req, new URL(req.url, 'http://localhost').pathname);
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(result));
    } catch (error) {
      if (!error.status) console.error(error);
      res.writeHead(error.status ?? 500, { 'Content-Type': 'application/json' })
        .end(JSON.stringify({ message: error.status ? error.message : 'Something went wrong.' }));
    }
  });

  return server;
}


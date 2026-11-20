const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };
export const legacyServices = new Set(['snow','lawn','cleaning']);
export const snowServices = new Set(['snow','drivewaySnow','walkwayClear','entranceClear']);
const round = (numerator, denominator = 10000) => Math.floor((numerator + denominator / 2) / denominator);

// Money enters and leaves this calculation as integer cents. Categories never
// come from client input. Legacy services bypass all newly seeded modifiers/tax.
export function calculateQuote({ service, property, input, addOns = [], modifiers = [], coupon, taxBps = 1300 }) {
  const legacy = legacyServices.has(service.id);
  const items = [{ label: 'Base service', amountCents: service.price_cents }];
  const add = (label, amountCents) => { if (amountCents) items.push({ label, amountCents }); };
  if (legacy) add('Large property', property.size === 'Large' ? 1500 : 0);
  else for (const rule of modifiers) {
    const value = rule.dimension === 'property_size' ? property.size
      : rule.dimension === 'driveway_size' ? property.measurements?.driveway ?? 'medium'
        : rule.dimension === 'snow_depth' && snowServices.has(service.id) ? input.snowDepth ?? 'light' : null;
    if (value === rule.choice) add(rule.dimension.replaceAll('_',' ') + ': ' + rule.choice, rule.price_cents);
  }
  add('Urgent booking', input.urgent === true ? 2000 : 0);
  const ids = input.addOnIds ?? [];
  if (!Array.isArray(ids) || ids.length > 30 || ids.some(id => typeof id !== 'string') || new Set(ids).size !== ids.length) fail(400,'Choose valid add-ons.');
  if (input.snowDepth != null && (!snowServices.has(service.id) || !['light','moderate','heavy'].includes(input.snowDepth))) fail(400,'Choose a valid snow depth.');
  for (const id of ids) {
    const option = addOns.find(a => a.id === id && a.service_id === service.id && a.active);
    if (!option) fail(400,'An add-on is no longer available.');
    add(option.name, option.price_cents);
  }
  if (service.id === 'snow' && input.walkway === true && !ids.includes('snow-walkway')) add('Walkway clearing',1200);
  let subtotalCents = items.reduce((sum, item) => sum + item.amountCents,0);
  if (!legacy && subtotalCents < service.minimum_price_cents) {
    add('Minimum price adjustment', service.minimum_price_cents - subtotalCents);
    subtotalCents = service.minimum_price_cents;
  }
  const code = String(input.couponCode ?? (input.discount === true ? 'EDEN10' : '')).trim().toUpperCase();
  if (code && !coupon) fail(400,'Promo code is not recognized.');
  if (coupon && code) {
    if (!coupon.active) fail(400,'This promo code is inactive.');
    if (coupon.expires_at && new Date(coupon.expires_at).getTime() <= Date.now()) fail(400,'This promo code has expired.');
    if (coupon.max_uses != null && coupon.uses >= coupon.max_uses) fail(409,'This promo code has been used up.');
  }
  const discountCents = code ? round(subtotalCents * coupon.discount_bps) : 0;
  const rateBps = legacy ? 1300 : taxBps;
  const taxCents = round((subtotalCents - discountCents) * rateBps);
  // EDEN10 legacy booking calculation historically rounds once at the end.
  const totalCents = legacy && code === 'EDEN10'
    ? round(subtotalCents * 9000 * 11300, 100000000)
    : subtotalCents - discountCents + taxCents;
  return { items, subtotalCents, discountCents, taxCents: totalCents - subtotalCents + discountCents,
    taxName: 'Sales tax', taxRateBps: rateBps, totalCents, currency: service.currency ?? 'CAD',
    service_category: service.service_category, couponCode: code || null, paymentTiming: 'after_completion' };
}

export function createPricing(db) {
  async function quote(connection, user, input, locking = false) {
    if (user.role !== 'customer') fail(403,'Switch to customer mode.');
    if (!Number.isInteger(input.propertyId) || typeof input.service !== 'string' ||
      input.service.length > 20 || (input.couponCode != null && (typeof input.couponCode !== 'string' || input.couponCode.length > 40))) fail(400,'Choose a valid property, service and coupon.');
    for (const flag of ['urgent','walkway','discount']) if (input[flag] != null && typeof input[flag] !== 'boolean') fail(400,'Invalid booking option.');
    if (input.date != null && (!Number.isFinite(Date.parse(input.date)) || Date.parse(input.date) <= Date.now() || Date.parse(input.date)>Date.now()+366*86400000)) fail(400,'Choose a future date within one year.');
    const [[selected]] = await connection.execute('SELECT * FROM properties WHERE id=? AND owner=?',[input.propertyId,user.id]);
    const [[service]] = await connection.execute('SELECT * FROM services WHERE id=? AND active=1',[input.service]);
    if (!selected || !service) fail(404,'Property or service unavailable.');
    const property = { ...(typeof selected.details === 'string' ? JSON.parse(selected.details) : selected.details), id:selected.id, cityId:selected.city_id ?? null };
    const [addOns] = await connection.execute('SELECT * FROM add_ons WHERE service_id=? AND active=1',[service.id]);
    const [modifiers] = legacyServices.has(service.id) ? [[]] : await connection.execute('SELECT * FROM service_price_modifiers WHERE service_id=? AND active=1 ORDER BY dimension,choice',[service.id]);
    const [[tax]] = selected.city_id == null || legacyServices.has(service.id) ? [[]] : await connection.execute('SELECT rate_bps FROM city_tax_rates WHERE city_id=?',[selected.city_id]);
    const code = String(input.couponCode ?? (input.discount === true ? 'EDEN10' : '')).trim().toUpperCase();
    const [[coupon]] = code ? await connection.execute('SELECT * FROM coupons WHERE code=?'+(locking?' FOR UPDATE':''),[code]) : [[]];
    return { breakdown:calculateQuote({service,property,input,addOns,modifiers,coupon,taxBps:tax?.rate_bps ?? 1300}), property, service };
  }
  return {
    async quote(user,input) { return (await quote(db,user,input)).breakdown; },
    async place(user,input,validated) {
      if (typeof input.date !== 'string' || !Number.isFinite(Date.parse(input.date))) fail(400,'Choose a valid future date.');
      const c=await db.getConnection();
      try {
        await c.beginTransaction();
        const {breakdown,property,service}=await quote(c,user,input,true);
        if (input.expectedTotalCents != null && input.expectedTotalCents!==breakdown.totalCents) fail(409,'The quote changed. Review the updated total before booking.');
        const details={...validated,property,service:service.id,date:new Date(input.date).toISOString(),total:breakdown.totalCents/100,breakdown,
          options:{urgent:input.urgent===true,walkway:input.walkway===true,snowDepth:input.snowDepth??null,addOnIds:input.addOnIds??[]}};
        const [result]=await c.execute('INSERT INTO bookings (customer_id,details,service_category,quoted_total_cents,currency) VALUES (?,?,?,?,?)',
          [user.id,JSON.stringify(details),service.service_category,breakdown.totalCents,breakdown.currency]);
        if(breakdown.couponCode) {
          const [used]=await c.execute('UPDATE coupons SET uses=uses+1 WHERE code=? AND (max_uses IS NULL OR uses<max_uses)',[breakdown.couponCode]);
          if(!used.affectedRows) fail(409,'This promo code has been used up.');
          await c.execute('INSERT INTO coupon_redemptions (booking_id,coupon_code,customer_id) VALUES (?,?,?)',[result.insertId,breakdown.couponCode,user.id]);
        }
        await c.commit();
        return {...details,id:result.insertId,status:'searching',version:0,service_category:service.service_category,quoted_total_cents:breakdown.totalCents,currency:breakdown.currency};
      } catch(e) {await c.rollback();throw e;} finally {c.release();}
    },
  };
}

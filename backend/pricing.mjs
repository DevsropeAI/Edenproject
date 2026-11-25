import {bookingSchedule} from './booking-schedule.mjs';
import {propertyMeasurements} from './addresses.mjs';
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
    service_category: service.service_category, couponCode: code || null, couponDiscountBps:code?coupon.discount_bps:0,paymentTiming: 'after_completion' };
}

export function createPricing(db) {
  async function quote(connection, user, input, locking = false, editContext) {
    if (user.role !== 'customer') fail(403,'Switch to customer mode.');
    if (!Number.isInteger(input.propertyId) || typeof input.service !== 'string' ||
      input.service.length > 20 || (input.couponCode != null && (typeof input.couponCode !== 'string' || input.couponCode.length > 40))) fail(400,'Choose a valid property, service and coupon.');
    if(input.bookingType!=null&&!['one_time','long_term'].includes(input.bookingType))fail(400,'Choose one-time or long-term service.');
    for (const flag of ['urgent','walkway','discount']) if (input[flag] != null && typeof input[flag] !== 'boolean') fail(400,'Invalid booking option.');
    bookingSchedule(input,false);
    const [[selected]] = await connection.execute('SELECT * FROM properties WHERE id=? AND owner=?',[input.propertyId,user.id]);
    const [[service]] = await connection.execute('SELECT * FROM services WHERE id=? AND active=1',[input.service]);
    if (!selected || !service) fail(404,'Property or service unavailable.');
    const property = { ...(typeof selected.details === 'string' ? JSON.parse(selected.details) : selected.details),...(editContext?.propertyOverrides??{}), id:selected.id, cityId:selected.city_id ?? null };
    const [addOns] = await connection.execute('SELECT * FROM add_ons WHERE service_id=? AND active=1',[service.id]);
    const [modifiers] = legacyServices.has(service.id) ? [[]] : await connection.execute('SELECT * FROM service_price_modifiers WHERE service_id=? AND active=1 ORDER BY dimension,choice',[service.id]);
    const [[tax]] = selected.city_id == null || legacyServices.has(service.id) ? [[]] : await connection.execute('SELECT rate_bps FROM city_tax_rates WHERE city_id=?',[selected.city_id]);
    const code = String(input.couponCode ?? (input.discount === true ? 'EDEN10' : '')).trim().toUpperCase();
    let [[coupon]] = code ? await connection.execute('SELECT * FROM coupons WHERE code=?'+(locking?' FOR UPDATE':''),[code]) : [[]];
    // Editing the same booking retains its original coupon; it does not redeem
    // it again or fail because the already-redeemed coupon reached its limit.
    if(code&&editContext?.breakdown?.couponCode===code){
      const rate=editContext.breakdown.couponDiscountBps??coupon?.discount_bps;
      if(!Number.isInteger(rate))fail(409,'The original coupon cannot be repriced. Contact support.');
      coupon={discount_bps:rate,active:1,max_uses:null,expires_at:null};
    }
    return { breakdown:calculateQuote({service,property,input,addOns,modifiers,coupon,taxBps:tax?.rate_bps ?? 1300}), property, service };
  }
  return {
    async quote(user,input) { return (await quote(db,user,input)).breakdown; },
    async edit(user,id,input,preview=false){
      if(user.role!=='customer')fail(403,'Switch to customer mode.');
      const c=await db.getConnection();
      try{await c.beginTransaction();
        const [[row]]=await c.execute('SELECT * FROM bookings WHERE id=? AND customer_id=? FOR UPDATE',[id,user.id]);
        if(!row)fail(404,'Booking unavailable.');
        if(row.status!=='searching'||row.contractor_id!=null)fail(409,'Only unaccepted bookings can be edited.');
        const details=typeof row.details==='string'?JSON.parse(row.details):row.details;
        if(typeof input.notes!=='string'||input.notes.length>2000||input.propertyNotes!=null&&(typeof input.propertyNotes!=='string'||input.propertyNotes.length>1000))fail(400,'Check booking and property instructions.');
        if(input.measurements!=null&&(typeof input.measurements!=='object'||Array.isArray(input.measurements)))fail(400,'Check property measurements.');
        const schedule=bookingSchedule(input);
        const overrides={...(details.propertyOverrides??{}),notes:input.propertyNotes?.trim()??details.property.notes??'',
          measurements:propertyMeasurements({...details.property.measurements,...input.measurements})};
        let breakdown=details.breakdown;
        let totalCents=row.quoted_total_cents??Math.round(details.total*100);
        const measurementsChanged=JSON.stringify(propertyMeasurements(details.property.measurements??{}))!==JSON.stringify(overrides.measurements);
        if(!legacyServices.has(details.service)&&details.options&&breakdown&&measurementsChanged){
          const result=await quote(c,user,{...details.options,propertyId:details.property.id,service:details.service,...schedule,
            utcOffsetMinutes:input.utcOffsetMinutes,couponCode:breakdown.couponCode??''},true,{...details,propertyOverrides:overrides});
          breakdown={...result.breakdown,service_category:row.service_category??breakdown.service_category};totalCents=breakdown.totalCents;
        }else if(!legacyServices.has(details.service)&&measurementsChanged&&(!details.options||!breakdown))fail(409,'This older booking lacks pricing options. Contact support before changing its measurements.');
        if(preview){await c.commit();return {totalCents,currency:row.currency??'CAD',breakdown};}
        if(input.expectedTotalCents!=null?(!Number.isInteger(input.expectedTotalCents)||input.expectedTotalCents!==totalCents):totalCents!==(row.quoted_total_cents??Math.round(details.total*100)))fail(409,'The quote changed. Review the latest total before saving.');
        const next={...details,...schedule,notes:input.notes.trim(),property:{...details.property,...overrides},propertyOverrides:overrides,total:totalCents/100,
          ...(breakdown?{breakdown}:{})};
        const [updated]=await c.execute("UPDATE bookings SET details=?,quoted_total_cents=?,version=version+1 WHERE id=? AND version=? AND status='searching' AND contractor_id IS NULL",[JSON.stringify(next),totalCents,id,row.version]);
        if(!updated.affectedRows)fail(409,'The booking changed. Refresh and try again.');
        await c.commit();return {...next,id,status:row.status,version:row.version+1,quoted_total_cents:totalCents,service_category:row.service_category,currency:row.currency};
      }catch(e){await c.rollback();throw e;}finally{c.release();}
    },
    async place(user,input,validated) {
      const schedule=bookingSchedule(input);
      const bookingType=input.bookingType ?? 'one_time';
      if(!['one_time','long_term'].includes(bookingType))fail(400,'Choose one-time or long-term service.');
      const c=await db.getConnection();
      try {
        await c.beginTransaction();
        const {breakdown,property,service}=await quote(c,user,input,true);
        if (input.expectedTotalCents != null && input.expectedTotalCents!==breakdown.totalCents) fail(409,'The quote changed. Review the updated total before booking.');
        const details={...validated,...schedule,bookingType,...(bookingType==='long_term'?{recurring:false}:{}),property,service:service.id,total:breakdown.totalCents/100,breakdown,
          options:{urgent:input.urgent===true,walkway:input.walkway===true,snowDepth:input.snowDepth??null,addOnIds:input.addOnIds??[]}};
        const dispatchStatus = bookingType === 'long_term' ? 'pending_admin' : 'open';
        const [result]=await c.execute('INSERT INTO bookings (customer_id,details,service_category,quoted_total_cents,currency,dispatch_status) VALUES (?,?,?,?,?,?)',
          [user.id,JSON.stringify({...details,serviceTitle:service.title}),service.service_category,breakdown.totalCents,breakdown.currency,dispatchStatus]);
        if(breakdown.couponCode) {
          const [used]=await c.execute('UPDATE coupons SET uses=uses+1 WHERE code=? AND (max_uses IS NULL OR uses<max_uses)',[breakdown.couponCode]);
          if(!used.affectedRows) fail(409,'This promo code has been used up.');
          await c.execute('INSERT INTO coupon_redemptions (booking_id,coupon_code,customer_id) VALUES (?,?,?)',[result.insertId,breakdown.couponCode,user.id]);
        }
        await c.commit();
        return {...details,serviceTitle:service.title,id:result.insertId,status:'searching',version:0,dispatch_status:dispatchStatus,service_category:service.service_category,quoted_total_cents:breakdown.totalCents,currency:breakdown.currency};
      } catch(e) {await c.rollback();throw e;} finally {c.release();}
    },
  };
}

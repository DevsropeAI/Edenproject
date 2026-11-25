import { randomBytes } from 'node:crypto';
const fail = (status,message) => {throw Object.assign(new Error(message),{status});};
const integer = (v,max=1000000) => Number.isInteger(v)&&v>=0&&v<=max;
const str = (v,max=100) => typeof v==='string'&&v.trim().length>0&&v.length<=max;
export async function catalogAdmin({path,method,read,run,db}) {
  const match=/^\/api\/admin\/(services|add-ons|pricing-rules|taxes|coupons)(?:\/([A-Za-z0-9_-]{1,40}))?$/.exec(path);
  if(!match)return undefined;
  const [,kind,id]=match;
  const table={services:'services','add-ons':'add_ons','pricing-rules':'service_price_modifiers',taxes:'city_tax_rates',coupons:'coupons'}[kind];
  if(method==='GET'&&!id)return run(`SELECT * FROM ${table}`);
  if(method!=='POST'||(!id&&kind!=='services'))return undefined;
  const b=await read();
  if(kind==='services') {
    if(!['Active','Inactive'].includes(b.status)||!integer(b.priceCents)||b.priceCents<100)fail(400,'Check price and status.');
    if((!id||b.title!=null)&&!str(b.title,80))fail(400,'Enter a service name (up to 80 characters).');
    if(b.minimumPriceCents!=null&&!integer(b.minimumPriceCents))fail(400,'Invalid minimum price.');
    if(b.estimatedDurationMinutes!=null&&(!integer(b.estimatedDurationMinutes,14400)||b.estimatedDurationMinutes<1))fail(400,'Invalid duration.');
    if(b.shortDescription!=null&&(typeof b.shortDescription!=='string'||b.shortDescription.length>300))fail(400,'Invalid description.');
    if(b.imageUrl!=null&&(typeof b.imageUrl!=='string'||b.imageUrl.length>500||b.imageUrl&&!/^https:\/\//.test(b.imageUrl)))fail(400,'Use an HTTPS image URL.');
    if(!id){
      const serviceId='svc'+randomBytes(8).toString('hex');
      await run(`INSERT INTO services (id,title,price_cents,active,short_description,image_url,estimated_duration_minutes,minimum_price_cents,currency)
        VALUES (?,?,?,?,?,?,?,?,?)`,serviceId,b.title.trim(),b.priceCents,Number(b.status==='Active'),b.shortDescription??'',b.imageUrl||null,b.estimatedDurationMinutes??60,b.minimumPriceCents??0,'CAD');
      return {saved:true,id:serviceId};
    }
    // Renaming a catalog entry also preserves legacy primary-service matching.
    const connection=db ? await db.getConnection() : null;
    const execute=connection ? async(sql,...args)=>(await connection.execute(sql,args))[0] : run;
    try {
      if(connection)await connection.beginTransaction();
      if(b.title!=null){
        const [existing]=await execute('SELECT title FROM services WHERE id=? FOR UPDATE',id);
        if(!existing)fail(404,'Service unavailable.');
        await execute('UPDATE users SET service=? WHERE contractor=1 AND LOWER(service)=LOWER(?)',b.title.trim(),existing.title);
      }
      const r=await execute(`UPDATE services SET active=?,price_cents=?,title=COALESCE(?,title),
        minimum_price_cents=COALESCE(?,minimum_price_cents),estimated_duration_minutes=COALESCE(?,estimated_duration_minutes),
        short_description=COALESCE(?,short_description),image_url=COALESCE(?,image_url) WHERE id=?`,
        Number(b.status==='Active'),b.priceCents,b.title?.trim()??null,b.minimumPriceCents??null,b.estimatedDurationMinutes??null,b.shortDescription??null,b.imageUrl??null,id);
      if(!r.affectedRows)fail(404,'Service unavailable.');
      if(connection)await connection.commit();
      return {saved:true};
    }catch(e){if(connection)await connection.rollback();throw e;}finally{connection?.release();}
  }
  if(kind==='taxes') {
    if(!/^\d+$/.test(id)||!integer(b.rateBps,10000))fail(400,'Check city and tax rate.');
    await run('INSERT INTO city_tax_rates (city_id,rate_bps) VALUES (?,?) ON DUPLICATE KEY UPDATE rate_bps=?',Number(id),b.rateBps,b.rateBps);return {saved:true};
  }
  if(typeof b.active!=='boolean')fail(400,'Choose an active status.');
  if(kind==='coupons') {
    if(!/^[A-Z0-9_-]+$/.test(id)||!integer(b.discountBps,10000)||b.maxUses!=null&&!integer(b.maxUses,100000000)||b.expiresAt!=null&&!Number.isFinite(Date.parse(b.expiresAt)))fail(400,'Check coupon fields.');
    if(id==='EDEN10'&&(b.discountBps!==1000||!b.active||b.maxUses!=null||b.expiresAt!=null))fail(400,'EDEN10 must retain its existing unlimited 10% behavior.');
    await run(`INSERT INTO coupons (code,discount_bps,active,expires_at,max_uses) VALUES (?,?,?,?,?)
      ON DUPLICATE KEY UPDATE discount_bps=?,active=?,expires_at=?,max_uses=?`,id,b.discountBps,b.active,b.expiresAt?new Date(b.expiresAt):null,b.maxUses??null,b.discountBps,b.active,b.expiresAt?new Date(b.expiresAt):null,b.maxUses??null);
    return {saved:true};
  }
  if(!str(b.serviceId,20)||!integer(b.priceCents))fail(400,'Check service and price.');
  if(kind==='add-ons') {
    if(!str(b.name))fail(400,'Enter an add-on name.');
    if(id==='snow-walkway'&&(b.serviceId!=='snow'||b.priceCents!==1200||!b.active))fail(400,'Existing walkway behavior must remain unchanged.');
    await run(`INSERT INTO add_ons (id,service_id,name,price_cents,active) VALUES (?,?,?,?,?)
      ON DUPLICATE KEY UPDATE service_id=?,name=?,price_cents=?,active=?`,id,b.serviceId,b.name.trim(),b.priceCents,b.active,b.serviceId,b.name.trim(),b.priceCents,b.active);
  } else {
    const choices={property_size:['Standard','Small','Medium','Large'],driveway_size:['small','medium','large'],snow_depth:['light','moderate','heavy']};
    if(!choices[b.dimension]?.includes(b.choice)||['snow','lawn','cleaning'].includes(b.serviceId))fail(400,'Choose a supported modifier for an added service.');
    await run(`INSERT INTO service_price_modifiers (service_id,dimension,choice,price_cents,active) VALUES (?,?,?,?,?)
      ON DUPLICATE KEY UPDATE price_cents=?,active=?`,b.serviceId,b.dimension,b.choice,b.priceCents,b.active,b.priceCents,b.active);
  }
  return {saved:true};
}

export async function contractorServices({method,user,read,run,db}) {
  if(user.role!=='contractor')fail(403,'Switch to contractor mode.');
  if(method==='GET')return {serviceIds:(await run('SELECT service_id FROM contractor_services WHERE user_id=?',user.id)).map(r=>r.service_id)};
  if(method!=='POST')fail(405,'Use GET or POST.');
  const {serviceIds}=await read();
  if(!Array.isArray(serviceIds)||serviceIds.length>50||serviceIds.some(id=>!str(id,20))||new Set(serviceIds).size!==serviceIds.length)fail(400,'Choose valid services.');
  const c=await db.getConnection();
  try{await c.beginTransaction();
    for(const id of serviceIds){const [[s]]=await c.execute('SELECT id FROM services WHERE id=? AND active=1',[id]);if(!s)fail(400,'A selected service is unavailable.');}
    await c.execute('DELETE FROM contractor_services WHERE user_id=?',[user.id]);
    for(const id of serviceIds)await c.execute('INSERT INTO contractor_services (user_id,service_id) VALUES (?,?)',[user.id,id]);
    await c.commit();return {saved:true};
  }catch(e){await c.rollback();throw e;}finally{c.release();}
}

import { randomUUID } from 'node:crypto';
const fail=(status,message)=>{throw Object.assign(new Error(message),{status});};
const date=ms=>new Date(ms).toISOString().replace('T',' ').replace('Z','');
const parseTime=value=>typeof value==='string'?Date.parse(value):NaN;
const iso=column=>`DATE_FORMAT(${column}, '%Y-%m-%dT%H:%i:%s.%fZ')`;
const summaryColumns=`id, contractor_id AS contractorId, ${iso('started_at')} AS startedAt,
  ${iso('ended_at')} AS endedAt, status, distance_m AS distanceM,
  (SELECT COALESCE(MAX(sequence_no),0) FROM walking_points WHERE shift_id=walking_shifts.id) AS lastSequence`;

export function walkingConfig(env=process.env){
  const number=(key,fallback,min,max)=>{
    const value=Number(env[key]??fallback);
    if(!Number.isFinite(value)||value<min||value>max)throw Error('Invalid '+key);
    return value;
  };
  return {sampleSeconds:12,movementMetres:15,
    accuracyM:number('EDEN_WALKING_MAX_ACCURACY_M',50,5,200),
    gapSeconds:number('EDEN_WALKING_GAP_SECONDS',45,25,300),
    maxHours:number('EDEN_WALKING_MAX_HOURS',8,1,24),
    retentionDays:number('EDEN_WALKING_RETENTION_DAYS',90,1,365),
    cleanup:env.EDEN_ENABLE_WALKING_CLEANUP==='true'};
}
export function distanceMetres(a,b){
  const rad=v=>v*Math.PI/180;
  const v=Math.sin(rad(b.latitude-a.latitude)/2)**2+Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(rad(b.longitude-a.longitude)/2)**2;
  return 6371000*2*Math.atan2(Math.sqrt(v),Math.sqrt(Math.max(0,1-v)));
}
export function validateWalkingBatch(points,config,now=Date.now()){
  if(!Array.isArray(points)||!points.length||points.length>100)fail(400,'Upload between 1 and 100 points.');
  let previous=0;
  return points.map(p=>{
    const at=parseTime(p.recordedAt);
    if(!Number.isInteger(p.sequence)||p.sequence<=previous||p.sequence>4294967295||
      !Number.isFinite(p.latitude)||Math.abs(p.latitude)>90||!Number.isFinite(p.longitude)||Math.abs(p.longitude)>180||
      !Number.isFinite(p.accuracyM)||p.accuracyM<0||p.accuracyM>config.accuracyM||
      !Number.isFinite(at)||at>now+15000||typeof p.gapBefore!=='boolean')fail(400,'Invalid GPS point, accuracy, sequence or timestamp.');
    previous=p.sequence;return {...p,at};
  });
}

export function createWalking(db,config=walkingConfig()){
  const execute=async(sql,args=[]) => (await db.execute(sql,args))[0];
  async function transaction(task){const c=await db.getConnection();try{await c.beginTransaction();const r=await task(c);await c.commit();return r;}catch(e){await c.rollback();throw e;}finally{c.release();}}
  async function enabled(c,user){
    if(user.role!=='contractor')fail(403,'Switch to contractor mode.');
    const [[row]]=await c.execute('SELECT door_to_door_enabled FROM users WHERE id=? FOR UPDATE',[user.id]);
    if(!row?.door_to_door_enabled)fail(403,'Door-to-door access is not enabled.');
  }
  async function endExpired(){await execute(`UPDATE walking_shifts SET status='ended', ended_at=DATE_ADD(started_at, INTERVAL ? HOUR)
    WHERE status='active' AND started_at<=?`,[config.maxHours,date(Date.now()-config.maxHours*3600000)]);}
  async function policy(){const [row]=await execute('SELECT version,body,retention_days AS retentionDays,is_placeholder AS isPlaceholder FROM walking_policy_versions WHERE active=1 ORDER BY created_at DESC,version DESC LIMIT 1');return row??null;}
  return {
    config,
    async maintenance(){
      await endExpired();
      if(config.cleanup)await execute(`DELETE s FROM walking_shifts s JOIN walking_consents c ON c.id=s.consent_id
        JOIN walking_policy_versions p ON p.version=c.consent_version
        WHERE s.status='ended' AND s.ended_at<DATE_SUB(?,INTERVAL LEAST(?,p.retention_days) DAY)`,[date(Date.now()),config.retentionDays]);
    },
    async route({method,path,user,admin=false,body={},params=new URLSearchParams()}){
      if(admin){
        const toggle=/^\/api\/admin\/contractors\/([a-f0-9]{64})\/door-to-door$/.exec(path);
        if(toggle&&method==='POST'){
          if(typeof body.enabled!=='boolean')fail(400,'Choose enabled or disabled.');
          return transaction(async c=>{
            const [r]=await c.execute('UPDATE users SET door_to_door_enabled=? WHERE id=? AND contractor=1',[body.enabled,toggle[1]]);
            if(!r.affectedRows){const[[exists]]=await c.execute('SELECT id FROM users WHERE id=? AND contractor=1',[toggle[1]]);if(!exists)fail(404,'Contractor not found.');}
            if(!body.enabled)await c.execute("UPDATE walking_shifts SET status='ended',ended_at=? WHERE contractor_id=? AND status='active'",[date(Date.now()),toggle[1]]);
            return {enabled:body.enabled};
          });
        }
        if(path==='/api/admin/walking/policy'&&method==='POST'){
          if(typeof body.version!=='string'||!/^[a-zA-Z0-9_-]{1,40}$/.test(body.version)||typeof body.body!=='string'||body.body.trim().length<30||body.body.length>10000||!Number.isInteger(body.retentionDays)||body.retentionDays<1||body.retentionDays>365||typeof body.isPlaceholder!=='boolean')fail(400,'Check consent version, wording and retention.');
          return transaction(async c=>{
            const[[exists]]=await c.execute('SELECT version FROM walking_policy_versions WHERE version=?',[body.version]);if(exists)fail(409,'Publish a new version instead of changing accepted wording.');
            await c.execute('UPDATE walking_policy_versions SET active=0');
            await c.execute('INSERT INTO walking_policy_versions (version,body,retention_days,is_placeholder,active) VALUES (?,?,?,?,1)',[body.version,body.body.trim(),body.retentionDays,body.isPlaceholder]);return {saved:true};
          });
        }
        if(path==='/api/admin/walking/policy'&&method==='GET')return {policy:await policy()};
        if(path==='/api/admin/walking/shifts'&&method==='GET'){
          const where=[];const args=[];const contractor=params.get('contractor');
          if(contractor){if(!/^[a-f0-9]{64}$/.test(contractor))fail(400,'Invalid contractor.');where.push('contractor_id=?');args.push(contractor);}
          for(const [param,operator]of [['from','>='],['to','<']]){const value=params.get(param);if(value){if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value)))fail(400,'Choose valid UTC dates.');where.push('started_at'+operator+'?');args.push(date(Date.parse(value)+(param==='to'?86400000:0)));}}
          return {shifts:await execute('SELECT '+summaryColumns+' FROM walking_shifts'+(where.length?' WHERE '+where.join(' AND '):'')+' ORDER BY started_at DESC LIMIT 500',args)};
        }
        const points=/^\/api\/admin\/walking\/shifts\/([a-f0-9-]{36})\/points$/.exec(path);
        if(points&&method==='GET'){
          const [shift]=await execute('SELECT '+summaryColumns+' FROM walking_shifts WHERE id=?',[points[1]]);if(!shift)fail(404,'Shift not found.');
          const rows=await execute(`SELECT sequence_no AS sequence,latitude,longitude,accuracy_m AS accuracyM,${iso('recorded_at')} AS recordedAt,gap_before AS gapBefore FROM walking_points WHERE shift_id=? ORDER BY sequence_no LIMIT 10000`,[shift.id]);
          return {shift,points:rows};
        }
        return undefined;
      }
      if(!path.startsWith('/api/walking/'))return undefined;
      if(user.role!=='contractor')fail(403,'Switch to contractor mode.');
      if(method==='GET'&&path==='/api/walking/status'){
        const [account]=await execute('SELECT door_to_door_enabled FROM users WHERE id=?',[user.id]);
        if(!account?.door_to_door_enabled)return {enabled:false};
        await endExpired();const p=await policy();
        const [consent]=p?await execute('SELECT id FROM walking_consents WHERE contractor_id=? AND consent_version=?',[user.id,p.version]):[];
        const [shift]=await execute('SELECT '+summaryColumns+" FROM walking_shifts WHERE contractor_id=? AND status='active'",[user.id]);
        return {enabled:true,policy:p,consented:Boolean(consent),shift:shift??null,config:{...config,retentionDays:p?Math.min(config.retentionDays,p.retentionDays):config.retentionDays}};
      }
      return transaction(async c=>{
        await enabled(c,user);
        if(method==='POST'&&path==='/api/walking/consent'){
          const p=await policy();if(!p||body.version!==p.version)fail(409,'Consent wording changed. Please read it again.');
          await c.execute('INSERT IGNORE INTO walking_consents (id,contractor_id,consent_version,accepted_at) VALUES (?,?,?,?)',[randomUUID(),user.id,p.version,date(Date.now())]);return {accepted:true};
        }
        if(method==='POST'&&path==='/api/walking/shifts/start'){
          const p=await policy();if(!p)fail(503,'Consent wording is not configured.');
          const [[consent]]=await c.execute('SELECT id FROM walking_consents WHERE contractor_id=? AND consent_version=?',[user.id,p.version]);if(!consent)fail(403,'Read and accept the consent before starting a shift.');
          const [[active]]=await c.execute("SELECT id FROM walking_shifts WHERE contractor_id=? AND status='active'",[user.id]);if(active)fail(409,'A shift is already active.');
          const id=randomUUID();await c.execute('INSERT INTO walking_shifts (id,contractor_id,started_at,consent_id) VALUES (?,?,?,?)',[id,user.id,date(Date.now()),consent.id]);
          const [[shift]]=await c.execute('SELECT '+summaryColumns+' FROM walking_shifts WHERE id=?',[id]);return {shift};
        }
        const match=/^\/api\/walking\/shifts\/([a-f0-9-]{36})\/(points|stop)$/.exec(path);
        if(!match||method!=='POST')fail(404,'Walking endpoint not found.');
        const [[shift]]=await c.execute('SELECT '+summaryColumns+' FROM walking_shifts WHERE id=? AND contractor_id=? FOR UPDATE',[match[1],user.id]);if(!shift)fail(404,'Shift not found.');
        if(match[2]==='stop'){
          if(shift.status==='active')await c.execute("UPDATE walking_shifts SET status='ended',ended_at=? WHERE id=?",[date(Date.now()),shift.id]);return {stopped:true};
        }
        const start=parseTime(shift.startedAt);const now=Date.now();
        if(shift.status!=='active'||now-start>=config.maxHours*3600000)fail(409,'This shift is no longer active.');
        const points=validateWalkingBatch(body.points,config,now);
        const [[last]]=await c.execute(`SELECT sequence_no AS sequence,latitude,longitude,${iso('recorded_at')} AS recordedAt FROM walking_points WHERE shift_id=? ORDER BY sequence_no DESC LIMIT 1`,[shift.id]);
        let previous=last;let distance=Number(shift.distanceM);
        for(const p of points){
          if(p.at<start)fail(400,'A GPS point predates the shift.');
          if(previous&&p.sequence<=previous.sequence){
            const [[existing]]=await c.execute(`SELECT latitude,longitude,accuracy_m AS accuracyM,${iso('recorded_at')} AS recordedAt FROM walking_points WHERE shift_id=? AND sequence_no=?`,[shift.id,p.sequence]);
            if(!existing||existing.latitude!==p.latitude||existing.longitude!==p.longitude||parseTime(existing.recordedAt)!==p.at||existing.accuracyM!==p.accuracyM)fail(409,'A point sequence was reused with different data.');continue;
          }
          if(p.sequence!==(previous?.sequence??0)+1||previous&&p.at<=parseTime(previous.recordedAt))fail(400,'GPS points must arrive in sequence and time order.');
          const gap=p.gapBefore||!previous||p.at-parseTime(previous.recordedAt)>config.gapSeconds*1000;
          if(previous&&!gap)distance+=distanceMetres(previous,p);
          await c.execute('INSERT INTO walking_points (shift_id,sequence_no,latitude,longitude,accuracy_m,recorded_at,gap_before) VALUES (?,?,?,?,?,?,?,?)',[shift.id,p.sequence,p.latitude,p.longitude,p.accuracyM,date(p.at),gap]);
          previous={...p,recordedAt:new Date(p.at).toISOString()};
        }
        await c.execute('UPDATE walking_shifts SET distance_m=? WHERE id=?',[Math.round(distance*100)/100,shift.id]);
        return {accepted:true,lastSequence:previous?.sequence??0,distanceM:Math.round(distance*100)/100};
      });
    },
  };
}

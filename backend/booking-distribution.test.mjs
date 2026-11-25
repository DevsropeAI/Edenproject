import assert from 'node:assert/strict';
import {test} from 'node:test';
import {marketplace} from './marketplace.mjs';
import {createPricing} from './pricing.mjs';
import {assignLongTerm} from './long-term-dispatch.mjs';

const worker={id:'a'.repeat(64),role:'contractor',area:'Other country',service:'Other service'};
const detail={service:'custom',bookingType:'long_term',property:{id:1,address:'Street, Lahore',pin:{latitude:31.5,longitude:74.3}},notes:'Instructions',messages:[],total:75};
const row={id:1,status:'searching',version:0,customer_id:'owner',contractor_id:null,dispatch_status:'pending_admin',details:detail};

test('long-term requests are private until assignment; legacy pending and all one-time services are public',async()=>{
  const rows=[row,{...row,id:2,dispatch_status:'assigned',assigned_contractor_id:worker.id},{...row,id:3,dispatch_status:'assigned',assigned_contractor_id:'other'},
    {...row,id:4,details:{...detail,bookingType:'one_time'}},{...row,id:5,details:{...detail,bookingType:undefined}},{...row,id:6,details:{...detail,bookingType:'long_term'},dispatch_status:'open'}];
  const offers=await marketplace({method:'GET',path:'/api/bookings',user:worker,run:async()=>rows});
  assert.deepEqual(offers.map(job=>job.id),[2,4,5]);
});
test('direct acceptance cannot bypass long-term assignment or invite another contractor',async()=>{
  for(const booking of [row,{...row,dispatch_status:'assigned',assigned_contractor_id:'someone-else'},{...row,dispatch_status:'open'}]){
    await assert.rejects(marketplace({method:'POST',path:'/api/bookings/1',user:worker,read:async()=>({action:'accept'}),first:async sql=>sql.startsWith('SELECT b.*')?booking:undefined,run:async()=>assert.fail('Unauthorized write')}),{status:404});
  }
});
test('assigned contractor can accept a long-term request regardless of work city, specialty or availability',async()=>{
  const result=await marketplace({method:'POST',path:'/api/bookings/1',user:worker,read:async()=>({action:'accept'}),first:async sql=>sql.startsWith('SELECT b.*')?{...row,dispatch_status:'assigned',assigned_contractor_id:worker.id}:sql.includes('contractor_reviews')?{status:'Approved'}:sql.includes('preferences')?{offline:1}:undefined,run:async()=>({affectedRows:1})});
  assert.equal(result.status,'accepted');
});
test('decline, release and cancellation of long-term assignments return them to admin',async()=>{
  for(const [action,status] of [['decline','searching'],['release','accepted'],['cancel','enRoute']]){
    let writes=[];
    await marketplace({method:'POST',path:'/api/bookings/1',user:worker,read:async()=>({action}),first:async sql=>sql.startsWith('SELECT b.*')?{...row,status,dispatch_status:'assigned',assigned_contractor_id:worker.id,contractor_id:action==='decline'?null:worker.id}:undefined,run:async(sql,...args)=>{writes.push([sql,args]);return {affectedRows:1};}});
    if(action==='decline')assert.equal(writes[0][1][0],'pending_admin');
    else assert.match(writes[0][0],/dispatch_status = 'pending_admin', assigned_contractor_id = NULL/);
  }
});
test('creation routes by booking type, never by category, and keeps custom service prices server controlled',async()=>{
  for(const bookingType of ['one_time','long_term']){
    let saved;
    const c={beginTransaction:async()=>{},commit:async()=>{},rollback:async()=>{},release(){},execute:async(sql,args)=>{
      if(sql.startsWith('SELECT * FROM properties'))return [[{id:1,details:detail.property}]];
      if(sql.startsWith('SELECT * FROM services'))return [[{id:'custom',title:'Window Cleaning',price_cents:7500,minimum_price_cents:0,service_category:'large',currency:'CAD'}]];
      if(sql.startsWith('SELECT'))return [[]];
      if(sql.startsWith('INSERT INTO bookings'))saved=args;
      return [{insertId:1,affectedRows:1}];
    }};
    const pricing=createPricing({...c,getConnection:async()=>c});
    const input={propertyId:1,service:'custom',bookingType,scheduledDate:new Date(Date.now()+86400000).toISOString().slice(0,10),utcOffsetMinutes:0};
    const quote=await pricing.quote({role:'customer'},input);
    const result=await pricing.place({id:'owner',role:'customer'},{...input,expectedTotalCents:quote.totalCents},{notes:'',recurring:true,messages:[]});
    assert.equal(saved[5],bookingType==='long_term'?'pending_admin':'open');
    assert.equal(JSON.parse(saved[1]).bookingType,bookingType);
    if(bookingType==='long_term')assert.equal(JSON.parse(saved[1]).recurring,false);
    assert.equal(result.quoted_total_cents,quote.totalCents);
    assert.equal(JSON.parse(saved[1]).serviceTitle,'Window Cleaning');
    await assert.rejects(pricing.place({id:'owner',role:'customer'},{...input,bookingType:'other'},{}),{status:400});
  }
});
test('admin assignment locks the request and allows any active contractor, without city/service queries',async()=>{
  const events=[];
  const c={beginTransaction:async()=>events.push('begin'),commit:async()=>events.push('commit'),rollback:async()=>events.push('rollback'),release:()=>events.push('release'),execute:async(sql,args)=>{
    events.push(sql);
    if(sql.startsWith('SELECT * FROM bookings'))return [[row]];
    if(sql.startsWith('SELECT id FROM users'))return [[{id:worker.id}]];
    assert.doesNotMatch(sql,/city_id|contractor_services|service_category/);
    if(sql.startsWith('UPDATE'))assert.equal(args[1],worker.id);
    return [{affectedRows:1}];
  }};
  assert.deepEqual(await assignLongTerm({getConnection:async()=>c},1,{action:'assign',contractorId:worker.id}),{status:'assigned'});
  assert.deepEqual(events.slice(-2),['commit','release']);
  assert.match(events[1],/FOR UPDATE/);
});
test('admin cannot assign public, accepted, deleted or already assigned requests',async()=>{
  for(const change of [{details:{...detail,bookingType:'one_time'}},{status:'accepted'},{details:{...detail,customerDeleted:true}},{dispatch_status:'assigned'}]){
    let rollback=false;
    const c={beginTransaction:async()=>{},commit:async()=>assert.fail('Unexpected commit'),rollback:async()=>{rollback=true;},release(){},execute:async sql=>{assert.match(sql,/^SELECT \*/);return [[{...row,...change}]];}};
    await assert.rejects(assignLongTerm({getConnection:async()=>c},1,{action:'assign',contractorId:worker.id}),{status:409});
    assert.equal(rollback,true);
  }
});

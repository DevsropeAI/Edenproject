import assert from 'node:assert/strict';
import {test} from 'node:test';
import {bookingSchedule} from './booking-schedule.mjs';
import {createPricing} from './pricing.mjs';
import {marketplace} from './marketplace.mjs';

test('date-only scheduling accepts today without a time, validates calendar dates and preserves old ISO inputs',()=>{
  const now=Date.parse('2026-11-23T20:00:00Z');
  assert.deepEqual(bookingSchedule({scheduledDate:'2026-11-23'},true,now),{date:'2026-11-23T12:00:00.000Z',scheduledDate:'2026-11-23'});
  assert.equal(bookingSchedule({scheduledDate:'2026-11-24',utcOffsetMinutes:300},true,now).scheduledDate,'2026-11-24');
  for(const scheduledDate of ['2026-02-30','invalid','2026-11-22','2028-01-01'])assert.throws(()=>bookingSchedule({scheduledDate},true,now),e=>e.status===400);
  assert.throws(()=>bookingSchedule({scheduledDate:'2026-11-24',utcOffsetMinutes:9999},true,now),e=>e.status===400);
  assert.deepEqual(bookingSchedule({date:'2026-11-24T10:00:00Z'},true,now),{date:'2026-11-24T10:00:00.000Z'});
});

function editFixture(){
  const details={property:{id:1,size:'Standard',notes:'Gate',measurements:{driveway:'medium'}},service:'drivewaySnow',date:new Date(Date.now()+86400000).toISOString(),
    notes:'Old',total:48.31,options:{urgent:false,walkway:false,addOnIds:[]},breakdown:{totalCents:4831,couponCode:'EDEN5',couponDiscountBps:500,service_category:'small'}};
  const state={row:{id:1,customer_id:'owner',contractor_id:null,status:'searching',version:4,quoted_total_cents:4831,currency:'CAD',service_category:'small',details},updates:[],affectedRows:1};
  const c={beginTransaction:async()=>{},commit:async()=>{},rollback:async()=>{},release:()=>{},execute:async(sql,args)=>{
    if(sql.startsWith('SELECT * FROM bookings'))return [args[1]==='owner'?[state.row]:[]];
    if(sql.startsWith('SELECT * FROM properties'))return [[{id:1,details:details.property}]];
    if(sql.startsWith('SELECT * FROM services'))return [[{id:'drivewaySnow',price_cents:4000,minimum_price_cents:4000,service_category:'large',currency:'CAD'}]];
    if(sql.startsWith('SELECT * FROM service_price_modifiers'))return [[{dimension:'driveway_size',choice:'large',price_cents:1500},{dimension:'driveway_size',choice:'medium',price_cents:500}]];
    if(sql.startsWith('SELECT * FROM coupons'))return [[{discount_bps:500,active:0,expires_at:'2020-01-01',max_uses:1,uses:1}]];
    if(sql.startsWith('SELECT'))return [[]];
    state.updates.push([sql,args]);return [{affectedRows:state.affectedRows}];
  }};
  const api=createPricing({getConnection:async()=>c});
  const input={scheduledDate:new Date(Date.now()+86400000).toISOString().slice(0,10),notes:'New instructions',propertyNotes:'Use side gate',
    measurements:{driveway:'large',walkway:'long',frontYard:true,frontYardSize:'200 sq ft',backyard:false,backyardSize:''}};
  return {api,state,input,user:{id:'owner',role:'customer'}};
}

test('unaccepted job measurements preview and save a revised quote without modifying property or redeeming coupon twice',async()=>{
  const {api,state,input,user}=editFixture();
  const preview=await api.edit(user,1,input,true);assert.equal(preview.totalCents,5904);assert.equal(state.updates.length,0);
  const saved=await api.edit(user,1,{...input,expectedTotalCents:5904});
  assert.equal(saved.property.measurements.driveway,'large');assert.equal(saved.property.notes,'Use side gate');
  assert.equal(saved.propertyOverrides.measurements.frontYardSize,'200 sq ft');assert.equal(saved.service_category,'small');
  assert.equal(saved.breakdown.service_category,'small');
  assert.equal(state.updates.length,1);assert.ok(state.updates[0][0].startsWith('UPDATE bookings'));
  assert.equal(state.row.details.property.measurements.driveway,'medium');
});

test('edits reject ownership, acceptance, stale saves and invalid measurements',async()=>{
  const {api,state,input,user}=editFixture();
  await assert.rejects(()=>api.edit({id:'other',role:'customer'},1,input,true),e=>e.status===404);
  await assert.rejects(()=>api.edit({id:'owner',role:'contractor'},1,input,true),e=>e.status===403);
  await assert.rejects(()=>api.edit(user,1,{...input,measurements:{driveway:'invalid'}},true),e=>e.status===400);
  for(const status of ['accepted','enRoute','working','submitted','completed','cancelled']){
    state.row.status=status;await assert.rejects(()=>api.edit(user,1,input,true),e=>e.status===409);
  }
  state.row.status='searching';state.row.contractor_id='worker';await assert.rejects(()=>api.edit(user,1,input,true),e=>e.status===409);
  state.row.contractor_id=null;await assert.rejects(()=>api.edit(user,1,{...input,expectedTotalCents:1}),e=>e.status===409);
  state.affectedRows=0;await assert.rejects(()=>api.edit(user,1,{...input,expectedTotalCents:5904}),e=>e.status===409);
});

test('legacy service edits preserve stored totals even when measurement details change',async()=>{
  const {api,state,input,user}=editFixture();state.row.details.service='snow';state.row.details.total=66.10;state.row.quoted_total_cents=6610;
  assert.equal((await api.edit(user,1,input,true)).totalCents,6610);
});

test('accepting an offer retains booking-specific measurements over the saved property',async()=>{
  const response=await marketplace({method:'POST',path:'/api/bookings/1',user:{id:'worker',role:'contractor',area:'Lahore',service:'Snow removal'},read:async()=>({action:'accept'}),
    first:async sql=>sql.startsWith('SELECT b.*')?{id:1,status:'searching',version:1,customer_id:'owner',contractor_id:null,
      details:{service:'snow',property:{id:1,address:'Street, Lahore',measurements:{driveway:'large'}},propertyOverrides:{measurements:{driveway:'large'}}},
      current_property:{address:'Street, Lahore',measurements:{driveway:'medium'}}}:sql.includes('contractor_reviews')?{status:'Approved'}:undefined,
    run:async()=>({affectedRows:1})});
  assert.equal(response.property.measurements.driveway,'large');
});

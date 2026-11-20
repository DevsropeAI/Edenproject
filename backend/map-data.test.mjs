import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mapData } from './map-data.mjs';

test('admin sees fresh GPS, stale GPS, work-city fallback and unlocated contractors without fabricated pins',async()=>{
  const workers=[
    {id:'live',name:'Live',latitude:31.5,longitude:74.3,shared_at:Date.now(),preferences:{available:true}},
    {id:'old',name:'Old',latitude:31.6,longitude:74.4,shared_at:Date.now()-86400000,preferences:{}},
    {id:'city',name:'City',city_latitude:40.7,city_longitude:-74,city_name:'New York',city_state:'New York',city_country:'United States',preferences:{}},
    {id:'none',name:'No coordinates',area:'Texas',preferences:{}},
  ];
  const result=await mapData(async sql=>sql.startsWith('SELECT * FROM bookings')?[]:workers,{role:'admin'});
  assert.equal(result.contractors.length,4);assert.equal(result.markers.length,3);
  assert.equal(result.markers.find(m=>m.id==='contractor-live').online,true);
  assert.equal(result.markers.find(m=>m.id==='contractor-old').locationSource,'last_shared');
  const city=result.markers.find(m=>m.id==='contractor-city');
  assert.equal(city.latitude,40.7);assert.equal(city.locationSource,'work_city');assert.equal(city.online,false);
  assert.equal(city.details.workCity,'New York, New York, United States');
  assert.equal(result.contractors.find(m=>m.id==='contractor-none').locationSource,'unavailable');
});

test('contractor endpoint restricts worker locations to self and job pins to assignments',async()=>{
  const sqls=[];
  const result=await mapData(async(sql,...params)=>{sqls.push(sql);assert.ok(params.includes('self'));return [];},{id:'self',role:'contractor'});
  assert.ok(sqls[0].includes('WHERE contractor_id=?'));
  assert.ok(sqls[1].includes('AND u.id=?'));
  assert.equal(result.contractors,undefined);
  await assert.rejects(()=>mapData(async()=>[],{role:'customer'}),e=>e.status===403);
});

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createApi} from './server.mjs';
import {validateWorkPin,saveWorkPin} from './work-pin.mjs';
import {mapData} from './map-data.mjs';

const pin={latitude:31.51,longitude:74.34};
async function request(path,method,body,db,options={}) {
  const api=createApi({db,...options});
  return new Promise(resolve=>api.emit('request',{method,url:path,headers:{authorization:'Bearer session'},socket:{remoteAddress:'127.0.0.1'},async *[Symbol.asyncIterator](){yield Buffer.from(JSON.stringify(body));}},{setHeader(){},writeHead(status){this.status=status;return this;},end(raw){resolve({status:this.status,body:JSON.parse(raw)});}}));
}
test('work pins reject invalid coordinates and whitelist only numbers',()=>{
  for(const input of [null,[],{}, {latitude:'31',longitude:74},{latitude:91,longitude:0},{latitude:0,longitude:-181},{latitude:NaN,longitude:0}])assert.throws(()=>validateWorkPin(input),{status:400});
  assert.deepEqual(validateWorkPin({...pin,available:false}),pin);
});
test('work pin writes merge into existing preferences instead of replacing availability',async()=>{
  await saveWorkPin(async(sql,...args)=>{assert.match(sql,/JSON_MERGE_PATCH/);assert.equal(args[0],'owner');assert.deepEqual(JSON.parse(args[1]),{workPin:pin});},'owner',pin);
});
test('profile pin endpoint scopes reads/writes to the authenticated contractor and rejects customers',async()=>{
  const writes=[];
  let stored;
  const db={execute:async(sql,args)=>{
    if(sql.includes('FROM sessions'))return [[{id:'owner',role:'contractor',area:'Legacy area'}]];
    if(sql.startsWith('SELECT details FROM preferences'))return [[{details:stored}]];
    writes.push(args);stored=JSON.parse(args[1]);return [{affectedRows:1}];
  }};
  assert.equal((await request('/api/contractor/work-location','POST',{workPin:pin,userId:'other'},db)).status,200);
  assert.equal(writes[0][0],'owner');
  const saved=await request('/api/contractor/work-location','GET',{},db);
  assert.deepEqual(saved.body.workPin,pin);
  assert.equal(saved.body.area,'Legacy area');
  const customerDb={execute:async()=>[[{id:'customer',role:'customer'}]]};
  for(const method of ['GET','POST'])assert.equal((await request('/api/contractor/work-location',method,{workPin:pin},customerDb)).status,403);
  assert.equal((await request('/api/contractor/work-location','POST',{workPin:{latitude:1000,longitude:0}},db)).status,400);
  assert.equal(writes.length,1);
});
test('registration saves the account and work pin atomically without needing a city lookup',async()=>{
  const events=[];let userId;
  const c={beginTransaction:async()=>events.push('begin'),commit:async()=>events.push('commit'),rollback:async()=>events.push('rollback'),release:()=>events.push('release'),execute:async(sql,args)=>{
    if(sql.includes('INSERT INTO users')){userId=args[0];assert.equal(args[8],'Pinned work location');events.push('user');}
    else {assert.match(sql,/INSERT INTO preferences/);assert.equal(args[0],userId);assert.deepEqual(JSON.parse(args[1]).workPin,pin);events.push('pin');}
    return [{affectedRows:1}];
  }};
  const body={role:'contractor',name:'Contractor',email:'work@example.test',password:'password123',phone:'1234567890',service:'Snow removal',workPin:pin};
  const result=await request('/api/auth/register','POST',body,{execute:async()=>[[]],getConnection:async()=>c});
  assert.equal(result.status,200);
  assert.deepEqual(events,['begin','user','pin','commit','release']);
  const bad=await request('/api/auth/register','POST',{...body,role:'customer'},{execute:async()=>assert.fail('Unexpected write')});
  assert.equal(bad.status,400);
});
test('saved work pin is shown as a saved location, never as live GPS',async()=>{
  const result=await mapData(async(sql)=>sql.startsWith('SELECT * FROM bookings')?[]:[{id:'worker',name:'Contractor',preferences:{available:true,workPin:pin}}],{role:'admin'});
  assert.equal(result.markers[0].locationSource,'work_pin');
  assert.equal(result.markers[0].online,false);
  assert.equal(result.markers[0].latitude,pin.latitude);
});

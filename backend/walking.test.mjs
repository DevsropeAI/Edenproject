import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createWalking,walkingConfig,validateWalkingBatch,distanceMetres} from './walking.mjs';

test('walking batches validate accuracy, coordinates, order and timestamps',()=>{
  const config=walkingConfig({});const p={sequence:1,latitude:31.5,longitude:74.3,accuracyM:10,recordedAt:new Date().toISOString(),gapBefore:true};
  assert.equal(validateWalkingBatch([p],config).length,1);
  for(const change of [{latitude:91},{longitude:181},{accuracyM:51},{sequence:0},{recordedAt:'invalid'},{gapBefore:'yes'}])assert.throws(()=>validateWalkingBatch([{...p,...change}],config),e=>e.status===400);
  assert.throws(()=>validateWalkingBatch([p,p],config),e=>e.status===400);
  assert.ok(distanceMetres(p,{...p,latitude:31.5001})>10);
});

function mockWalking(){
  const now=Date.now();const state={enabled:true,consented:true,shift:null,points:[],policy:{version:'v1',body:'Consent',retentionDays:90},maintenance:[]};
  const execute=async(sql,args=[])=>{
    if(sql.startsWith('SELECT door_to_door_enabled'))return [[{door_to_door_enabled:state.enabled}]];
    if(sql.startsWith('SELECT version,body'))return [[state.policy]];
    if(sql.startsWith('SELECT id FROM walking_consents'))return [state.consented?[{id:'consent'}]:[]];
    if(sql.startsWith('SELECT id FROM walking_shifts'))return [state.shift?.status==='active'?[{id:state.shift.id}]:[]];
    if(sql.startsWith('INSERT INTO walking_shifts')){state.shift={id:args[0],contractorId:args[1],startedAt:args[2].replace(' ','T')+'Z',status:'active',distanceM:0,lastSequence:0};return [{affectedRows:1}];}
    if(sql.startsWith('SELECT id, contractor_id')){
      if(sql.includes('AND contractor_id')&&args[1]!==state.shift?.contractorId)return [[]];
      return [state.shift?[{...state.shift}]:[]];
    }
    if(sql.startsWith('SELECT sequence_no'))return [state.points.length?[state.points.at(-1)]:[]];
    if(sql.startsWith('SELECT latitude,longitude'))return [state.points.filter(p=>p.sequence===args[1])];
    if(sql.startsWith('INSERT INTO walking_points')){state.points.push({sequence:args[1],latitude:args[2],longitude:args[3],accuracyM:args[4],recordedAt:args[5].replace(' ','T')+'Z',gapBefore:args[6]});return [{affectedRows:1}];}
    if(sql.startsWith('UPDATE walking_shifts SET distance_m')){state.shift.distanceM=args[0];return [{affectedRows:1}];}
    if(sql.startsWith("UPDATE walking_shifts SET status='ended',ended_at")){state.shift.status='ended';return [{affectedRows:1}];}
    if(sql.startsWith('UPDATE walking_shifts')||sql.startsWith('DELETE s FROM')){state.maintenance.push(sql);return [{affectedRows:0}];}
    return [[]];
  };
  const connection={execute,beginTransaction:async()=>{},commit:async()=>{},rollback:async()=>{},release:()=>{}};
  const db={execute,getConnection:async()=>connection};
  const api=createWalking(db,walkingConfig({EDEN_ENABLE_WALKING_CLEANUP:'true'}));
  const user={id:'worker',role:'contractor'};
  const call=(path,body={},caller=user)=>api.route({method:'POST',path,user:caller,body});
  return {state,api,call,now};
}

test('consent, enabled flag, ownership and stopped shift are enforced',async()=>{
  const {state,call}=mockWalking();
  state.enabled=false;await assert.rejects(()=>call('/api/walking/shifts/start'),e=>e.status===403);
  state.enabled=true;state.consented=false;await assert.rejects(()=>call('/api/walking/shifts/start'),e=>e.status===403);
  state.consented=true;const {shift}=await call('/api/walking/shifts/start');
  await assert.rejects(()=>call('/api/walking/shifts/'+shift.id+'/points',{}, {id:'other',role:'contractor'}),e=>e.status===404);
  await assert.rejects(()=>call('/api/walking/shifts/start',{}, {id:'customer',role:'customer'}),e=>e.status===403);
  await call('/api/walking/shifts/'+shift.id+'/stop');
  await assert.rejects(()=>call('/api/walking/shifts/'+shift.id+'/points',{points:[]}),e=>e.status===409);
});

test('batch retries do not duplicate distance and tracking gaps are never joined',async()=>{
  const {call,state}=mockWalking();const {shift}=await call('/api/walking/shifts/start');
  const start=Date.parse(shift.startedAt);
  // Controlled timestamps remain inside active shift and within future tolerance.
  const p=(sequence,latitude,gapBefore)=>({sequence,latitude,longitude:74.3,accuracyM:10,recordedAt:new Date(start+sequence).toISOString(),gapBefore});
  const points=[p(1,31.5,true),p(2,31.5001,false),p(3,32,true)];
  const result=await call('/api/walking/shifts/'+shift.id+'/points',{points});
  assert.ok(result.distanceM>10&&result.distanceM<12);
  const retried=await call('/api/walking/shifts/'+shift.id+'/points',{points});
  assert.equal(retried.distanceM,result.distanceM);assert.equal(state.points.length,3);
  await state; // No persistent database is used by this test.
});

test('retention maintenance expires stale shifts and gates deletion behind config',async()=>{
  const {api,state}=mockWalking();await api.maintenance();
  assert.ok(state.maintenance.some(s=>s.includes('DATE_ADD')));
  assert.ok(state.maintenance.some(s=>s.includes('DELETE s FROM')&&s.includes('LEAST')));
});

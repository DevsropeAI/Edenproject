import assert from 'node:assert/strict';
import {test} from 'node:test';
import {catalogAdmin} from './catalog-routes.mjs';
import {createApi} from './server.mjs';

const valid={title:'Window Cleaning',priceCents:7500,status:'Active',shortDescription:'Windows and frames',estimatedDurationMinutes:60,minimumPriceCents:0,imageUrl:''};
test('admin creates an arbitrary service with cents and a stable ID; category is not selected',async()=>{
  const calls=[];
  const result=await catalogAdmin({path:'/api/admin/services',method:'POST',read:async()=>valid,run:async(...args)=>{calls.push(args);return {affectedRows:1};}});
  assert.match(result.id,/^svc[a-f0-9]{16}$/);
  assert.match(calls[0][0],/^INSERT INTO services/);
  assert.doesNotMatch(calls[0][0],/service_category/);
  assert.deepEqual(calls[0].slice(1),[result.id,'Window Cleaning',7500,1,'Windows and frames',null,60,0,'CAD']);
});
test('invalid service input is rejected before any write',async()=>{
  for(const change of [{title:''},{title:'x'.repeat(101)},{priceCents:1.5},{priceCents:99},{status:'Other'},{imageUrl:'javascript:alert(1)'},{estimatedDurationMinutes:0},{minimumPriceCents:-1}]){
    await assert.rejects(catalogAdmin({path:'/api/admin/services',method:'POST',read:async()=>({...valid,...change}),run:async()=>assert.fail('Unexpected write')}),{status:400});
  }
});
test('renaming preserves contractor primary service and edits atomically without changing old orders',async()=>{
  const events=[];
  const connection={beginTransaction:async()=>events.push('begin'),commit:async()=>events.push('commit'),rollback:async()=>events.push('rollback'),release:()=>events.push('release'),execute:async(sql,args)=>{
    events.push([sql,args]);
    if(sql.startsWith('SELECT'))return [[{title:'Old service'}]];
    assert.doesNotMatch(sql,/bookings/);
    return [{affectedRows:1}];
  }};
  await catalogAdmin({path:'/api/admin/services/custom',method:'POST',read:async()=>({...valid,status:'Inactive'}),db:{getConnection:async()=>connection}});
  assert.equal(events[0],'begin');
  assert.match(events[2][0],/^UPDATE users SET service=/);
  assert.equal(events[3][1][0],0);
  assert.deepEqual(events.slice(-2),['commit','release']);
});
test('service creation endpoint rejects non-admin credentials',async()=>{
  const api=createApi({db:{execute:async()=>assert.fail('Unexpected database call')},adminKey:'admin-test',servicesPricing:true});
  const response=await new Promise(resolve=>api.emit('request',{method:'POST',url:'/api/admin/services',headers:{authorization:'Bearer contractor-session'},socket:{remoteAddress:'127.0.0.1'}},{setHeader(){},writeHead(status){this.status=status;return this;},end(){resolve(this.status);}}));
  assert.equal(response,401);
});

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {browserMapConfig} from './browser-map-config.mjs';
import {resolveAdminMapConfig} from '../admin/app/map-config.mjs';
import {createApi} from './server.mjs';

const key='AIzaBrowserForTestOnly';
test('the same reader accepts the existing name and the canonical browser key name',()=>{
  assert.equal(browserMapConfig({eden_map_api:key}).key,key);
  assert.equal(browserMapConfig({EDEN_GOOGLE_MAPS_WEB_KEY:key,eden_map_api:'AIzaOldTestOnly'}).key,key);
  assert.equal(browserMapConfig({EDEN_GOOGLE_MAPS_WEB_KEY:' ',eden_map_api:key}).key,key);
  assert.deepEqual(browserMapConfig({eden_map_api:'not-a-google-key'}),{key:'',mapId:'DEMO_MAP_ID'});
});
test('configuration exports only browser Maps settings, never server/OAuth/database credentials',()=>{
  const config=browserMapConfig({eden_map_api:key,EDEN_GOOGLE_MAPS_MAP_ID:'custom-map',CLIENT_SECRET:'oauth-secret',GOOGLE_MAPS_SERVER_API_KEY:'server-key',EDEN_ADMIN_KEY:'admin-secret',EDEN_MYSQL_URL:'database-secret'});
  assert.deepEqual(config,{key,mapId:'custom-map'});
});
test('admin prefers shared backend configuration and preserves old admin-only deployments',()=>{
  assert.deepEqual(resolveAdminMapConfig({key,mapId:'backend-map'},{EDEN_GOOGLE_MAPS_WEB_KEY:'old-local'}),{key,mapId:'backend-map'});
  assert.equal(resolveAdminMapConfig(undefined,{eden_map_api:key}).key,key);
  assert.equal(resolveAdminMapConfig(undefined,{EDEN_GOOGLE_MAPS_WEB_KEY:key}).key,key);
  assert.equal(resolveAdminMapConfig({key:'',mapId:'DEMO_MAP_ID'},{}).key,'');
});
async function request(token) {
  const api=createApi({db:{execute:async()=>[[]]},adminKey:'test-admin'});
  return new Promise(resolve=>api.emit('request',{method:'GET',url:'/api/admin/map',headers:{authorization:'Bearer '+token},socket:{remoteAddress:'127.0.0.1'}},{setHeader(){},writeHead(status){this.status=status;return this;},end(raw){resolve({status:this.status,body:JSON.parse(raw)});}}));
}
test('existing authenticated map endpoint delivers the backend browser key; unauthorized requests do not',async()=>{
  const names=['eden_map_api','EDEN_GOOGLE_MAPS_WEB_KEY','EDEN_GOOGLE_MAPS_MAP_ID'];
  const previous=Object.fromEntries(names.map(name=>[name,process.env[name]]));
  try {
    delete process.env.EDEN_GOOGLE_MAPS_WEB_KEY;
    delete process.env.EDEN_GOOGLE_MAPS_MAP_ID;
    process.env.eden_map_api=key;
    const response=await request('test-admin');
    assert.equal(response.status,200);
    assert.deepEqual(response.body.browserMapConfig,{key,mapId:'DEMO_MAP_ID'});
    assert.deepEqual(response.body.markers,[]);
    const denied=await request('contractor-token');
    assert.equal(denied.status,401);
    assert.equal(JSON.stringify(denied.body).includes(key),false);
  } finally {
    for(const name of names)if(previous[name]===undefined)delete process.env[name];else process.env[name]=previous[name];
  }
});

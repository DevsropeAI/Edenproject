import assert from 'node:assert/strict';
import {test} from 'node:test';
import {calculateQuote,createPricing} from './pricing.mjs';
import {mapData} from './map-data.mjs';

test('original three totals retain urgent, walkway, 13 percent tax and EDEN10 behavior',()=>{
  // Golden cents captured from the committed quote engine before this change.
  // Floating-point recomputation incorrectly rounded some half-cent totals down.
  const totals={3000:[3390,3051],4500:[5085,4577],5000:[5650,5085],5700:[6441,5797],6000:[6780,6102],6500:[7345,6611],7200:[8136,7322],7700:[8701,7831],8000:[9040,8136],8500:[9605,8645],9200:[10396,9356],10000:[11300,10170],10500:[11865,10679],12000:[13560,12204]};
  let cases=0;
  for(const [id,price] of [['snow',4500],['lawn',3000],['cleaning',8500]])
    for(const size of ['Standard','Large'])for(const urgent of [false,true])for(const walkway of [false,true])for(const discount of [false,true]){
      const base=price+(size==='Large'?1500:0)+(urgent?2000:0)+(walkway&&id==='snow'?1200:0);
      const expected=totals[base][Number(discount)];
      const q=calculateQuote({service:{id,price_cents:price,service_category:'small'},property:{size,measurements:{driveway:'large'}},
        input:{urgent,walkway,discount},coupon:discount?{active:1,discount_bps:1000}:null,
        modifiers:[{dimension:'driveway_size',choice:'large',price_cents:9999}],taxBps:500});
      assert.equal(q.totalCents,expected,JSON.stringify({id,size,urgent,walkway,discount}));
      assert.equal(q.taxRateBps,1300);assert.ok(Number.isInteger(q.totalCents));cases++;
    }
  assert.equal(cases,48);
});

test('added services use modifiers, minimums, add-ons, city tax and validated coupons',()=>{
  const args={service:{id:'drivewaySnow',price_cents:4000,minimum_price_cents:4000,service_category:'small'},
    property:{size:'Large',measurements:{driveway:'large'}},input:{snowDepth:'heavy',addOnIds:['extra'],couponCode:'EDEN5'},
    addOns:[{id:'extra',service_id:'drivewaySnow',active:1,name:'Extra',price_cents:1000}],
    modifiers:[{dimension:'property_size',choice:'Large',price_cents:1500},{dimension:'driveway_size',choice:'large',price_cents:1500},{dimension:'snow_depth',choice:'heavy',price_cents:2500}],
    coupon:{active:1,discount_bps:500},taxBps:500};
  const q=calculateQuote(args);assert.equal(q.subtotalCents,10500);assert.equal(q.discountCents,525);assert.equal(q.totalCents,10474);
  assert.notEqual(calculateQuote({...args,taxBps:1300}).totalCents,q.totalCents);
  assert.throws(()=>calculateQuote({...args,coupon:{...args.coupon,expires_at:'2020-01-01'}}),/expired/);
  assert.throws(()=>calculateQuote({...args,coupon:{...args.coupon,max_uses:1,uses:1}}),/used up/);
  assert.throws(()=>calculateQuote({...args,input:{...args.input,addOnIds:['unknown']}}),/add-on/);
  assert.equal(calculateQuote({service:{id:'leaf',price_cents:4000,minimum_price_cents:5000},property:{},input:{}}).subtotalCents,5000);
});

test('walkway add-on cannot double charge existing walkway option',()=>{
  const q=calculateQuote({service:{id:'snow',price_cents:4500},property:{},input:{walkway:true,addOnIds:['snow-walkway']},
    addOns:[{id:'snow-walkway',service_id:'snow',active:1,name:'Walkway',price_cents:1200}]});
  assert.equal(q.totalCents,6441);
});

test('quote and booking share engine; category is server sourced and coupon use atomic',async()=>{
  const saved=[];let committed=false;
  const c={beginTransaction:async()=>{},commit:async()=>{committed=true;},rollback:async()=>{},release:()=>{},
    execute:async(sql,values)=>{
      if(sql.startsWith('SELECT * FROM properties'))return [[{id:1,city_id:1,details:{size:'Standard',address:'Street, Lahore'}}]];
      if(sql.startsWith('SELECT * FROM services'))return [[{id:'hardscaping',price_cents:30000,minimum_price_cents:30000,service_category:'large',currency:'CAD'}]];
      if(sql.startsWith('SELECT rate_bps'))return [[{rate_bps:1300}]];
      if(sql.startsWith('SELECT * FROM coupons'))return [[{code:'EDEN5',discount_bps:500,active:1}]];
      if(sql.startsWith('SELECT'))return [[]];
      saved.push([sql,values]);return [{insertId:22,affectedRows:1}];
    }};
  const pricing=createPricing({...c,getConnection:async()=>c});
  const input={propertyId:1,service:'hardscaping',date:new Date(Date.now()+86400000).toISOString(),couponCode:'EDEN5',service_category:'small'};
  const user={id:'customer',role:'customer'};
  const q=await pricing.quote(user,input);
  const result=await pricing.place(user,{...input,expectedTotalCents:q.totalCents},{notes:'',recurring:false,messages:[],review:''});
  assert.equal(result.service_category,'large');assert.equal(result.quoted_total_cents,q.totalCents);
  assert.equal(result.breakdown.totalCents,q.totalCents);assert.ok(committed);
  assert.equal(saved.find(([sql])=>sql.startsWith('INSERT INTO bookings'))[1][2],'large');
  assert.ok(saved.some(([sql])=>sql.startsWith('INSERT INTO coupon_redemptions')));
  await assert.rejects(()=>pricing.quote({role:'contractor'},input),e=>e.status===403);
  await assert.rejects(()=>pricing.place(user,{...input,expectedTotalCents:1},{}),e=>e.status===409);
});

test('contractor map queries only assignments and never exposes coupon or rule internals',async()=>{
  const response=await mapData(async(sql,...params)=>{
    if(sql.startsWith('SELECT * FROM bookings')){assert.ok(sql.includes('WHERE contractor_id=?'));assert.equal(params[0],'worker');
      return [{id:1,status:'accepted',service_category:'large',details:{service:'hardscaping',property:{pin:{latitude:31,longitude:74},address:'Exact'},notes:'Private',total:90,breakdown:{couponCode:'SECRET'}}}];}
    return [];
  },{id:'worker',role:'contractor'});
  assert.equal(response.markers[0].kind,'active');assert.equal(response.markers[0].category,'large');
  assert.equal(response.markers[0].details.breakdown,undefined);
});

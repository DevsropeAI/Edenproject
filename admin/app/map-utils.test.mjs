import assert from 'node:assert/strict';
import {test} from 'node:test';
import {matchesSearch,visibleMarker,fullAddress} from './map-utils.mjs';
const job={entity:'customer',kind:'active',category:'small',title:'Booking #12',bookingId:12,details:{property:{name:'Home',address:'Gulberg 2',structuredAddress:{street:'Mini Market',city:'Lahore',state:'Punjab',country:'Pakistan'}}}};
test('map search matches actual addresses, structured city/state, names and booking ids',()=>{
  for(const q of ['gulberg','GULBERG 2','lahore','mini market','12'])assert.equal(matchesSearch(job,q),true);
  assert.equal(matchesSearch(job,'texas'),false);
  assert.equal(matchesSearch({entity:'contractor',title:'Jane Smith',details:{workCity:'Austin, Texas, United States'}},'jane texas'),true);
});
test('map filters hide each layer and address display never serializes pin coordinates',()=>{
  assert.equal(visibleMarker(job,['customers','active'],''),true);
  assert.equal(visibleMarker(job,['customers','small'],''),false);
  assert.equal(visibleMarker({...job,kind:'large',category:'large'},['customers','large'],''),true);
  assert.equal(visibleMarker({entity:'contractor',title:'Jane'},['contractors'],'jane'),true);
  assert.equal(fullAddress(job.details.property),'Mini Market, Lahore, Punjab, Pakistan');
});

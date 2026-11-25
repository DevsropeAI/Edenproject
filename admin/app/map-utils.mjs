export const filterLabels = {
  customers: 'Customer jobs', contractors: 'Contractors', open: 'Open leads',
  active: 'Active jobs', completed: 'Completed jobs',
};
export function matchesSearch(marker, query) {
  const d=marker.details??{};
  const p=d.property??{};
  const a=p.structuredAddress??{};
  const terms=query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const text=[marker.title,marker.detail,marker.bookingId,d.name,d.email,d.phone,d.workCity,d.service,
    p.name,p.address,a.street,a.city,a.state,a.postalCode,a.country].filter(v=>v!=null).join(' ').toLocaleLowerCase();
  return terms.every(term=>text.includes(term));
}
export function visibleMarker(marker, filters, query) {
  if(!matchesSearch(marker,query))return false;
  if(marker.entity==='contractor')return filters.includes('contractors');
  if(!filters.includes('customers'))return false;
  return filters.includes(['active','completed'].includes(marker.kind)?marker.kind:'open');
}
export function fullAddress(property={}) {
  const a=property.structuredAddress;
  return a?[a.street,a.city,a.state,a.postalCode,a.country].filter(Boolean).join(', '):property.address??'Address not recorded';
}
export function statusLabel(value='') {
  return ({searching:'Open lead',accepted:'Accepted',enRoute:'On the way',arrived:'Arrived',working:'In progress',submitted:'Awaiting approval',completed:'Completed'})[value]??value;
}

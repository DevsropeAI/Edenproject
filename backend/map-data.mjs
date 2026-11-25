import { readFileSync } from 'node:fs';
export const markerConfig=JSON.parse(readFileSync(new URL('../shared/map_markers.json',import.meta.url),'utf8'));
const parse=value=>typeof value==='string'?JSON.parse(value):value;
const valid=pin=>pin&&Number.isFinite(pin.latitude)&&Number.isFinite(pin.longitude)&&Math.abs(pin.latitude)<=90&&Math.abs(pin.longitude)<=180;
export async function mapData(run,user,visibleBookings) {
  const admin=user.role==='admin';
  if(!admin&&user.role!=='contractor')throw Object.assign(new Error('Contractor or admin access required.'),{status:403});
  const rows=visibleBookings ? visibleBookings.map(job=>({id:job.id,status:job.status,service_category:job.service_category,details:job})) : admin ? await run('SELECT * FROM bookings ORDER BY id DESC LIMIT 500')
    : await run('SELECT * FROM bookings WHERE contractor_id=? ORDER BY id DESC LIMIT 500',user.id);
  const markers=[];
  for(const row of rows){
    const d=parse(row.details);
    if(row.status==='cancelled'||!valid(d.property?.pin))continue;
    const kind=row.status==='completed'?'completed':row.status==='searching'?'customer':'active';
    markers.push({id:'job-'+row.id,kind,entity:'customer',category:row.service_category??'small',...d.property.pin,
      title:'Booking #'+row.id,detail:d.service+' · '+row.status,status:row.status,bookingId:row.id,
      // Explicit whitelist, never return quote internals or prior assignments.
      details:{property:d.property,notes:d.notes,date:d.date,scheduledDate:d.scheduledDate,total:d.total,status:row.status,service:d.service}});
  }
  const workers=await run(`SELECT u.id,u.name,u.email,u.phone,u.area,u.service,u.blocked,
      c.name AS city_name,c.state AS city_state,c.country AS city_country,
      c.latitude AS city_latitude,c.longitude AS city_longitude,
      p.details AS preferences,l.latitude,l.longitude,l.shared_at
    FROM users u LEFT JOIN preferences p ON p.user_id=u.id
    LEFT JOIN cities c ON c.id=u.city_id
    LEFT JOIN booking_locations l ON l.booking_id=(
      SELECT bl.booking_id FROM booking_locations bl JOIN bookings b ON b.id=bl.booking_id
      WHERE b.contractor_id=u.id ORDER BY bl.shared_at DESC,bl.booking_id DESC LIMIT 1)
    WHERE u.contractor=1${admin?'':' AND u.id=?'}`, ...(admin?[]:[user.id]));
  const contractors=[];
  const seen=new Set();
  for(const w of workers){if(seen.has(w.id))continue;seen.add(w.id);
    const shared=valid(w)&&w.shared_at!=null;
    const cityPin={latitude:w.city_latitude,longitude:w.city_longitude};
    const hasCity=valid(cityPin);
    const preferences=parse(w.preferences??{});
    const workPin=valid(preferences.workPin)?preferences.workPin:null;
    const available=!w.blocked&&preferences.available!==false;
    const online=shared&&Date.now()-Number(w.shared_at)<30000&&available;
    const workCity=[w.city_name,w.city_state,w.city_country].filter(Boolean).join(', ')||w.area||'Not set';
    const locationSource=online?'live':workPin?'work_pin':shared?'last_shared':hasCity?'work_city':'unavailable';
    const pin=online?{latitude:w.latitude,longitude:w.longitude}:workPin??(shared?{latitude:w.latitude,longitude:w.longitude}:cityPin);
    const record={id:'contractor-'+w.id,kind:'contractor',entity:'contractor',title:w.name,
      detail:online?'Live location':workPin?'Saved work location':shared?'Last shared location':hasCity?'Work city · approximate location':'No saved map location',
      online,locationSource,details:{name:w.name,email:w.email,phone:w.phone,workCity,service:w.service,
        available,lastSharedAt:shared?Number(w.shared_at):null}};
    if(admin)contractors.push(record);
    if(shared||hasCity||workPin)markers.push({...record,...pin});
  }
  return {markers,...(admin?{contractors}:{}),config:markerConfig,
    notice:admin?'Contractors show live GPS when available, otherwise a saved work pin, last shared location or approximate work-city centre. No coordinates are invented. Up to 500 bookings are shown.'
      :'Your available offers, assigned jobs and location are mapped. Saved work pins are separate from live GPS sharing.'};
}

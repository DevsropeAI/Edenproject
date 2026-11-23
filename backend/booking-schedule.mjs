const fail=message=>{throw Object.assign(new Error(message),{status:400});};

// Date-only bookings retain the old ISO date field for older clients. Noon UTC
// is an internal compatibility value, never a time selected/promised to users.
export function bookingSchedule(input,required=true,now=Date.now()) {
  if(input.scheduledDate!=null){
    const day=input.scheduledDate;
    const offset=input.utcOffsetMinutes??0;
    if(typeof day!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Number.isInteger(offset)||Math.abs(offset)>840)fail('Choose a valid service date.');
    const ms=Date.parse(day+'T00:00:00Z');
    if(!Number.isFinite(ms)||new Date(ms).toISOString().slice(0,10)!==day)fail('Choose a valid service date.');
    const today=new Date(now+offset*60000).toISOString().slice(0,10);
    if(day<today||ms>Date.parse(today+'T00:00:00Z')+365*86400000)fail('Choose today or a date within the next year.');
    return {date:day+'T12:00:00.000Z',scheduledDate:day};
  }
  if(input.date==null&&!required)return {};
  const ms=typeof input.date==='string'?Date.parse(input.date):NaN;
  if(!Number.isFinite(ms)||ms<=now||ms>now+366*86400000)fail('Choose a valid future date.');
  return {date:new Date(ms).toISOString()};
}

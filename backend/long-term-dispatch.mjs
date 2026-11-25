const fail=(status,message)=>{throw Object.assign(new Error(message),{status});};

// Called only after admin authentication in server.mjs. Use the booking lock to
// serialize assignment against customer edits/deletes and other administrators.
export async function assignLongTerm(db,id,body) {
  if(body.action!=='assign'||typeof body.contractorId!=='string'||!/^[a-f0-9]{64}$/.test(body.contractorId))fail(400,'Choose a contractor.');
  if(body.note!=null&&(typeof body.note!=='string'||body.note.length>2000))fail(400,'Keep the admin note under 2,000 characters.');
  const c=await db.getConnection();
  try {
    await c.beginTransaction();
    const [[row]]=await c.execute('SELECT * FROM bookings WHERE id=? FOR UPDATE',[id]);
    const details=typeof row?.details==='string'?JSON.parse(row.details):row?.details;
    if(!row||details?.bookingType!=='long_term'||details.customerDeleted||row.status!=='searching'||row.contractor_id||row.dispatch_status!=='pending_admin')fail(409,'This long-term request is no longer awaiting assignment.');
    const [[contractor]]=await c.execute('SELECT id FROM users WHERE id=? AND contractor=1 AND blocked=0 FOR UPDATE',[body.contractorId]);
    if(!contractor)fail(404,'Contractor unavailable.');
    // No work-city or service restriction: the admin explicitly chooses who sees it.
    // A new assignment can invite a contractor who previously declined/released it.
    details.releasedBy=(details.releasedBy??[]).filter(value=>value!==body.contractorId);
    await c.execute('DELETE FROM declined_jobs WHERE booking_id=? AND contractor_id=?',[id,body.contractorId]);
    const [result]=await c.execute("UPDATE bookings SET details=?,dispatch_status='assigned',assigned_contractor_id=?,assigned_at=NOW(),admin_note=?,version=version+1 WHERE id=? AND version=? AND status='searching' AND contractor_id IS NULL AND dispatch_status='pending_admin'",[JSON.stringify(details),body.contractorId,body.note?.trim()||null,id,row.version]);
    if(!result.affectedRows)fail(409,'This request changed. Refresh and try again.');
    await c.commit();
    return {status:'assigned'};
  }catch(error){await c.rollback();throw error;}finally{c.release();}
}

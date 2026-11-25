import { updateStatus, createService, dispatchJob } from './actions';
import { DocumentPreview } from './document-preview';
import MarketplaceMap from './marketplace-map';
import {setWalkingAccess} from './walking-actions';

const statuses = {
  Customers: ['Active', 'Blocked'],
  Contractors: ['Active', 'Blocked'],
  Support: ['Open', 'In review', 'Resolved'],
  Services: ['Active', 'Inactive'],
  Verification: ['Pending', 'Approved', 'Rejected'],
};

function Record({ section, search, record }) {
  const types = { Support: 'support', Services: 'services', Verification: 'verification', Payments: 'payments' };

  const refundOptions = record.status === 'refund_requested' ? ['Approve refund', 'Decline refund']
    : record.status === 'refund_processing' ? ['Approve refund'] : [];
  const options = section === 'Payments' ? refundOptions : statuses[section];
  const canCancel = section === 'Orders' && !['completed', 'cancelled'].includes(record.status);

  return (
    <article className="record">
      <div><h3>{record.title}</h3><p>{record.detail}</p></div>
      {section === 'Verification' && <DocumentPreview record={record} />}
      {section==='Contractors'&&<form action={setWalkingAccess.bind(null,record.id)} className="walking-access">
        <input type="hidden" name="enabled" value={String(!record.doorToDoorEnabled)}/>
        <button type="submit" role="switch" aria-checked={Boolean(record.doorToDoorEnabled)} aria-label={`Door-to-door access for ${record.title}`}>
          Door-to-door <span>{record.doorToDoorEnabled?'Enabled':'Disabled'}</span>
        </button>
      </form>}
      {canCancel ? (
        <form action={updateStatus.bind(null, section, search)} className="record-actions">
          <span>{record.status}</span>
          <input type="hidden" name="type" value="orders" />
          <input type="hidden" name="id" value={record.id} />
          <input type="hidden" name="status" value="cancelled" />
          <button type="submit">Cancel booking</button>
        </form>
      ) : options?.length ? (
        <form action={updateStatus.bind(null, section, search)} className="record-actions">
          <input type="hidden" name="type" value={types[section] ?? 'accounts'} />
          {section === 'Services' && <label>Price (CAD) <input name="price" type="number" min="1" max="10000" step="0.01" required defaultValue={record.priceCents / 100} /></label>}
          {section === 'Services' && <ServiceFields record={record} />}
          <input type="hidden" name="id" value={record.id} />
          <select key={record.status} name="status" aria-label={'Status for ' + record.title} defaultValue={section === 'Payments' ? options[0] : record.status}>
            {options.map(status => <option key={status} disabled={status === 'Pending'}>{status}</option>)}
          </select>
          <button type="submit" disabled={section === 'Verification' && !record.complete}>Save</button>
        </form>
      ) : <span>{record.status}</span>}
    </article>
  );
}

export function Dashboard({ data, section, search, result, mapData, mapError, mapKey, mapId }) {
  const query = search.trim().toLowerCase();
  const records = data[section].filter(({ title, detail, status }) =>
    [title, detail, status].some(value => value.toLowerCase().includes(query)),
  );
  const metrics = [
    ['Orders', data.Orders.length],
    ['Customers', data.Customers.length],
    ['Contractors', data.Contractors.length],
    ['Open support requests', data.Support.filter(ticket => ticket.status !== 'Resolved').length],
    ['Long-term requests', data.LongTermJobs?.length ?? 0],
  ];

  return (
    <div className="shell">
      <aside>
        <a className="brand" href="/">Eden <span>Admin</span></a>
        <nav aria-label="Operations">
          {Object.keys(data).map(name => (
            <a key={name} href={'/?section=' + encodeURIComponent(name)} aria-current={name === section ? 'page' : undefined}>
              {name === 'LongTermJobs' ? 'Long-term requests' : name}
            </a>
          ))}
        </nav>
      </aside>
      <main>
        <header><h1>Marketplace operations</h1></header>
        <section className="metrics" aria-label="Marketplace metrics">
          {metrics.map(([label, count]) => <article key={label}><span>{label}</span><strong>{count}</strong></article>)}
        </section>
        <section className="records">
          <div className="toolbar">
            <h2>{section === 'LongTermJobs' ? 'Long-term requests' : section}</h2>
            {section!=='Map'&&<form action="/" method="get" className="record-actions">
              <input type="hidden" name="section" value={section} />
              <label>Search <input key={section + ':' + search} type="search" name="search" defaultValue={search} /></label>
              <button type="submit">Search</button>
            </form>}
          </div>
          {result === 'saved' && <p role="status">Saved.</p>}
          {result === 'error' && <p role="alert">Could not save. Check the record and try again.</p>}
          {section === 'Services' && <details className="service-create"><summary>Add service</summary>
            <p>Active services appear in customer booking and contractor service selection.</p>
            <form action={createService} className="service-fields"><ServiceFields /><label>Base price (CAD)<input name="price" type="number" min="1" max="10000" step="0.01" required /></label><label>Status<select name="status"><option>Active</option><option>Inactive</option></select></label><button type="submit">Create service</button></form>
          </details>}
          {section==='Map'&&mapData&&<MarketplaceMap data={mapData} search={search} contractors={data.Contractors} mapKey={mapKey} mapId={mapId}/>}
          {section==='Map'&&mapError&&<p role="alert">Could not load the map. Check that the backend is running, then <a href="/?section=Map">try again</a>.</p>}
          {section!=='Map'&&!records.length && <p>No matching records.</p>}
          {section === 'LongTermJobs' ? records.map(record => <LongTermRequest key={record.id} record={record} contractors={data.Contractors} section={section} search={search}/>) : records.map(record => <Record key={section + record.id} section={section} search={search} record={record} />)}
        </section>
      </main>
    </div>
  );
}




function ServiceFields({record}) {
  return <div className="service-fields">
    <label>Service name<input name="title" maxLength={80} required defaultValue={record?.title ?? ''}/></label>

  </div>;
}

function LongTermRequest({record, contractors, section, search}) {
  const measurements=record.measurements ?? {};
  const yard=(key)=>measurements[key] ? ['Included',measurements[key+'Size']].filter(Boolean).join(' · ') : 'Not included';
  const facts=[['Service date',record.scheduledDate?.slice(0,10)],['Price',`CAD ${Number(record.total).toFixed(2)}`],
    ['Driveway',measurements.driveway],['Walkway',measurements.walkway],['Front yard',yard('frontYard')],['Backyard',yard('backyard')]];
  return <article className="long-term-request">
    <header className="request-heading"><div><span className="request-eyebrow">Awaiting assignment</span><h3>{record.title}</h3><p>{record.detail}</p></div><span className="request-number">#{record.id}</span></header>
    <div className="request-content"><section aria-label="Job information"><h4>Job information</h4><p className="request-address">{record.address}</p>
      <dl className="request-facts">{facts.filter(([,value])=>value!=null&&value!=='').map(([label,value])=><div key={label}><dt>{label}</dt><dd>{String(value)}</dd></div>)}</dl>
      {(record.notes||record.propertyNotes)&&<div className="request-instructions"><h4>Instructions</h4>{record.notes&&<p>{record.notes}</p>}{record.propertyNotes&&<p>{record.propertyNotes}</p>}</div>}
    </section><form action={dispatchJob.bind(null,record.id,section,search)} className="request-assignment"><h4>Assign this request</h4>
      <label htmlFor={'contractor-'+record.id}>Contractor</label><select id={'contractor-'+record.id} name="contractorId" required defaultValue=""><option value="" disabled>Choose a contractor</option>{contractors.filter(c=>c.status==='Active').map(c=><option value={c.id} key={c.id}>{c.title} — {c.detail}</option>)}</select>
      <label htmlFor={'note-'+record.id}>Admin note <span>(optional)</span></label><input id={'note-'+record.id} name="note" maxLength={2000}/>
      <button type="submit">Assign request</button>
    </form></div>
  </article>;
}

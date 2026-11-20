import { updateStatus } from './actions';
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
          {section === 'Services' && <label>Category <select name="service_category" defaultValue={record.service_category??'small'}><option value="small">Small</option><option value="large">Large</option></select></label>}
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

export function Dashboard({ data, section, search, result, mapData }) {
  const query = search.trim().toLowerCase();
  const records = data[section].filter(({ title, detail, status }) =>
    [title, detail, status].some(value => value.toLowerCase().includes(query)),
  );
  const metrics = [
    ['Orders', data.Orders.length],
    ['Customers', data.Customers.length],
    ['Contractors', data.Contractors.length],
    ['Open support requests', data.Support.filter(ticket => ticket.status !== 'Resolved').length],
  ];

  return (
    <div className="shell">
      <aside>
        <a className="brand" href="/">Eden <span>Admin</span></a>
        <nav aria-label="Operations">
          {Object.keys(data).map(name => (
            <a key={name} href={'/?section=' + encodeURIComponent(name)} aria-current={name === section ? 'page' : undefined}>
              {name}
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
            <h2>{section}</h2>
            {section!=='Map'&&<form action="/" method="get" className="record-actions">
              <input type="hidden" name="section" value={section} />
              <label>Search <input key={section + ':' + search} type="search" name="search" defaultValue={search} /></label>
              <button type="submit">Search</button>
            </form>}
          </div>
          {result === 'saved' && <p role="status">Saved.</p>}
          {result === 'error' && <p role="alert">Could not save. Check the record and try again.</p>}
          {section==='Map'&&mapData&&<MarketplaceMap data={mapData} search={search} contractors={data.Contractors}/>}
          {section!=='Map'&&!records.length && <p>No matching records.</p>}
          {records.map(record => <Record key={section + record.id} section={section} search={search} record={record} />)}
        </section>
      </main>
    </div>
  );
}

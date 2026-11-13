'use client';

import { useState } from 'react';

const initial = {
  Orders: [
    { id: 'ED-104', title: 'Snow removal', detail: 'Maple House · CAD 50.85', status: 'Searching' },
    { id: 'ED-103', title: 'Lawn mowing', detail: 'Oak House · CAD 33.90', status: 'Completed' },
  ],
  Customers: [{ id: 'CU-01', title: 'Avery Morgan', detail: 'Toronto', status: 'Active' }],
  Contractors: [{ id: 'CO-01', title: 'Jordan Lee', detail: 'Toronto · Snow removal', status: 'Pending' }],
  Services: [{ id: 'SV-01', title: 'Snow removal', detail: 'Base price CAD 45', status: 'Active' }],
  Support: [{ id: 'SP-12', title: 'Review work photos', detail: 'Order ED-104', status: 'Open' }],
};

const statuses = {
  Orders: ['Searching', 'Assigned', 'Completed', 'Cancelled'],
  Customers: ['Active', 'Blocked'],
  Contractors: ['Pending', 'Approved', 'Rejected', 'Suspended'],
  Services: ['Active', 'Inactive'],
  Support: ['Open', 'In review', 'Resolved'],
};

export default function Dashboard() {
  const [data, setData] = useState(initial);
  const [section, setSection] = useState('Orders');
  const [search, setSearch] = useState('');
  const query = search.trim().toLowerCase();
  const records = data[section].filter(({ id, title, detail, status }) =>
    [id, title, detail, status].some(value => value.toLowerCase().includes(query)),
  );
  const metrics = [
    ['Orders', data.Orders.length],
    ['Completed', data.Orders.filter(order => order.status === 'Completed').length],
    ['Contractors pending', data.Contractors.filter(person => person.status === 'Pending').length],
    ['Open support requests', data.Support.filter(ticket => ticket.status !== 'Resolved').length],
  ];

  function update(id, status) {
    setData(current => ({
      ...current,
      [section]: current[section].map(record => record.id === id ? { ...record, status } : record),
    }));
  }

  return (
    <div className="shell">
      <aside>
        <a className="brand" href="/">Eden <span>Admin</span></a>
        <nav aria-label="Operations">
          {Object.keys(data).map(name => (
            <button key={name} aria-pressed={name === section} onClick={() => { setSection(name); setSearch(''); }}>
              {name}
            </button>
          ))}
        </nav>
      </aside>
      <main>
        <header><h1>Marketplace operations</h1><p>Demo workspace · Sample records</p></header>
        <section className="metrics" aria-label="Marketplace metrics">
          {metrics.map(([label, count]) => <article key={label}><span>{label}</span><strong>{count}</strong></article>)}
        </section>
        <section className="records">
          <div className="toolbar">
            <h2>{section}</h2>
            <label>Search <input type="search" value={search} onChange={event => setSearch(event.target.value)} /></label>
          </div>
          {!records.length && <p>No matching records.</p>}
          {records.map(record => (
            <article className="record" key={record.id}>
              <div><small>{record.id}</small><h3>{record.title}</h3><p>{record.detail}</p></div>
              <select aria-label={`Status for ${record.id}`} value={record.status} onChange={event => update(record.id, event.target.value)}>
                {statuses[section].map(status => <option key={status}>{status}</option>)}
              </select>
            </article>
          ))}
        </section>
      </main>
    </div>
  );
}

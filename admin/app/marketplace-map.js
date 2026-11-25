'use client';
import { useEffect, useMemo, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { filterLabels, fullAddress, matchesSearch, statusLabel, visibleMarker } from './map-utils.mjs';
import { loadGoogleMaps } from './google-map-sdk.mjs';
import { googleMapAdapter } from './google-map-adapter.mjs';
import WalkingRoutes from './walking-routes';

function SearchIcon(){return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>;}
function MarkerSymbol({kind,config,offline=false}) {
  const s=config[kind];
  return <span aria-hidden="true" className={`map-symbol ${s.shape==='circle'?'map-symbol--circle':'map-symbol--pin'} ${offline?'map-symbol--offline':''}`} style={{'--marker-color':s.color}}>
    <span>{kind==='completed'?<svg viewBox="0 0 20 20"><path d="m4 10 4 4 8-8"/></svg>:kind==='active'?<span className="map-symbol__ring"/>:null}</span>
  </span>;
}
function InfoRow({label,children}){return children!=null&&children!==''?<div className="map-detail__row"><dt>{label}</dt><dd>{children}</dd></div>:null;}
function DetailsCard({marker,onClose}) {
  const d=marker.details??{};const worker=marker.entity==='contractor';const p=d.property??{};
  const date=d.date?new Date(d.date):null;
  const scheduledLabel=d.scheduledDate??(date&&!Number.isNaN(date.getTime())?date.toLocaleString():null);
  return <section className="map-detail" aria-label={`Details for ${marker.title}`}>
    <div className="map-detail__top"><span>{worker?'CONTRACTOR':'BOOKING DETAILS'}</span><button type="button" onClick={onClose} aria-label="Close details"><svg width="18" height="18" viewBox="0 0 20 20" stroke="currentColor" strokeWidth="1.8"><path d="m4 4 12 12M16 4 4 16"/></svg></button></div>
    <h3>{worker?marker.title:p.name||marker.title}</h3>
    <span className={`map-detail__status ${worker?'map-detail__status--worker':''}`}>{worker?marker.detail:statusLabel(marker.status)}</span>
    {worker&&<p className="map-detail__hint">{marker.locationSource==='work_city'?'This is the centre of the saved work city, not a live GPS position.':marker.locationSource==='unavailable'?'No saved city coordinates or shared GPS location yet.':marker.locationSource==='last_shared'?'Last shared position. The contractor is not sharing a fresh live update.':'Fresh location shared by the contractor.'}</p>}
    <dl>
      {worker?<><InfoRow label="Work location">{d.workCity}</InfoRow><InfoRow label="Primary service">{d.service}</InfoRow><InfoRow label="Availability">{d.available?'Available for jobs':'Unavailable'}</InfoRow><InfoRow label="Email">{d.email?<a href={`mailto:${d.email}`}>{d.email}</a>:null}</InfoRow><InfoRow label="Phone">{d.phone?<a href={`tel:${d.phone}`}>{d.phone}</a>:null}</InfoRow><InfoRow label="Last shared">{d.lastSharedAt?new Date(d.lastSharedAt).toLocaleString():null}</InfoRow></>
        :<><InfoRow label="Booking">#{marker.bookingId}</InfoRow><InfoRow label="Service">{d.service?.replace(/([a-z])([A-Z])/g,'$1 $2')}</InfoRow><InfoRow label="Address">{fullAddress(p)}</InfoRow><InfoRow label="Property">{[p.type,p.size].filter(Boolean).join(' · ')}</InfoRow><InfoRow label="Scheduled">{scheduledLabel}</InfoRow><InfoRow label="Quoted total">{typeof d.total==='number'?new Intl.NumberFormat(undefined,{style:'currency',currency:'CAD'}).format(d.total):null}</InfoRow><InfoRow label="Instructions">{d.notes||p.notes||'No special instructions'}</InfoRow>
          {p.measurements&&<><InfoRow label="Driveway">{p.measurements.driveway}</InfoRow><InfoRow label="Walkway">{p.measurements.walkway}</InfoRow><InfoRow label="Front yard">{p.measurements.frontYard?'Yes':'No'}</InfoRow><InfoRow label="Backyard">{p.measurements.backyard?'Yes':'No'}</InfoRow></>}
        </>}
    </dl>
    {!worker&&p.photo&&<img className="map-detail__photo" src={`data:image/jpeg;base64,${p.photo}`} alt="Property"/>}
  </section>;
}

export default function MarketplaceMap({ data, search='', contractors:walkingContractors=[], mapKey, mapId }) {
  const element=useRef(null);const mapRef=useRef(null);const layerRef=useRef(null);const libraryRef=useRef(null);const viewKey=useRef(null);
  const router=useRouter();const [pending,startTransition]=useTransition();
  const [ready,setReady]=useState(false);
  const [mapAttempt,setMapAttempt]=useState(0);
  const [walking,setWalking]=useState(false);
  const [filters,setFilters]=useState(Object.keys(filterLabels));
  const [query,setQuery]=useState(search);const [selected,setSelected]=useState(null);const [error,setError]=useState('');
  const visible=useMemo(()=>data.markers.filter(m=>visibleMarker(m,filters,query)),[data.markers,filters,query]);
  const contractors=useMemo(()=>(data.contractors??data.markers.filter(m=>m.entity==='contractor')).filter(m=>matchesSearch(m,query)),[data,query]);
  const selectedMarker=[...data.markers,...(data.contractors??[])].find(m=>m.id===selected);
  useEffect(()=>{const timer=setInterval(()=>startTransition(()=>router.refresh()),15000);return()=>clearInterval(timer);},[router]);
  useEffect(()=>{
    let disposed=false;let map;let observer;
    setReady(false);setError('');
    const timeout=setTimeout(()=>{if(!disposed)setError('The map is taking too long to load. Retry the map or refresh this page.');},15000);
    loadGoogleMaps(mapKey).then(g=>{
      if(disposed)return;
      const {map:createdMap,api:L}=googleMapAdapter(g,element.current,mapId);
      libraryRef.current=L;
      map=createdMap;
      mapRef.current=map;layerRef.current=L.layerGroup().addTo(map);
      // Layout can settle after hydration or change when the walking panel opens.
      // Re-measure the same map rather than replacing its layers or tiles.
      observer=new ResizeObserver(()=>map.invalidateSize({pan:false}));
      observer.observe(element.current);
      map.invalidateSize({pan:false});
      viewKey.current=null;
      clearTimeout(timeout);setError('');
      map.on('click',()=>setSelected(null));setReady(true);
    }).catch(()=>{if(!disposed)setError('Map could not load. Refresh to retry.');});
    return()=>{disposed=true;clearTimeout(timeout);observer?.disconnect();map?.remove();mapRef.current=null;layerRef.current=null;};
  },[mapAttempt,mapKey,mapId]);
  useEffect(()=>{
    if(!ready||!mapRef.current)return;
    const L=libraryRef.current;const layer=layerRef.current;layer.clearLayers();
    for(const m of visible){
      const s=data.config[m.kind];const circle=s.shape==='circle';
      const root=document.createElement('span');root.className=`map-marker ${circle?'map-marker--circle':'map-marker--pin'} ${m.online===false?'map-marker--offline':''} ${m.kind==='active'?'map-marker--active':''}`;
      root.style.setProperty('--marker-color',s.color);root.style.setProperty('--marker-size',`${s.size}px`);
      if(m.online===false)root.style.opacity=String(data.config.offlineOpacity);
      const badge=document.createElement('span');badge.className='map-marker__badge';
      if(m.kind==='completed')badge.textContent='✓';
      root.append(badge);
      L.marker([m.latitude,m.longitude],{title:`${m.title}: ${m.detail}`,icon:L.divIcon({html:root,className:'eden-map-marker',iconSize:[48,48],iconAnchor:[24,24]})}).addTo(layer).on('click',()=>setSelected(m.id));
    }
    const key=JSON.stringify([query,filters]);
    if(visible.length&&viewKey.current!==key){mapRef.current.fitBounds(visible.map(m=>[m.latitude,m.longitude]),{maxZoom:14,padding:[45,45]});viewKey.current=key;}
  },[ready,visible,data.config,query,filters]);
  const focusWorker=worker=>{
    setSelected(worker.id);const marker=data.markers.find(m=>m.id===worker.id);
    if(marker&&mapRef.current)mapRef.current.setView([marker.latitude,marker.longitude],13);
  };
  return <div className="operations-map">
    <div className="map-filter-chips"><button type="button" aria-pressed={walking} onClick={()=>setWalking(v=>!v)}>Door-to-door routes</button></div>
    {walking&&<WalkingRoutes mapRef={mapRef} libraryRef={libraryRef} ready={ready} contractors={walkingContractors} config={data.config.walking}/>}
    <div className="operations-map__heading"><div><h3>Marketplace overview</h3><p>Explore jobs and contractor work locations.</p></div><button className="map-refresh" type="button" disabled={pending} onClick={()=>startTransition(()=>router.refresh())}>{pending?'Updating…':'Refresh map'}</button></div>
    <div className="map-search"><SearchIcon/><input type="search" value={query} onChange={e=>{setQuery(e.target.value);setSelected(null);}} placeholder="Address, city, contractor or booking…" aria-label="Search saved map locations"/>{query&&<button type="button" onClick={()=>setQuery('')}>Clear</button>}</div>
    <p className="map-search__hint">Search saved marketplace records. This is not a worldwide address lookup.</p>
    <div className="map-filter-chips" role="group" aria-label="Map layers">{Object.entries(filterLabels).map(([key,label])=><button key={key} type="button" aria-pressed={filters.includes(key)} onClick={()=>{setSelected(null);setFilters(prev=>prev.includes(key)?prev.filter(f=>f!==key):[...prev,key]);}}>{label}</button>)}</div>
    <div className="map-legend" aria-label="Map legend">{['customer','contractor','active','completed'].map(kind=><span key={kind}><MarkerSymbol kind={kind} config={data.config}/>{({customer:'Open lead',contractor:'Contractor',active:'Active job',completed:'Completed'})[kind]}</span>)}<small>Solid blue: live · Outlined blue: last location / work city</small></div>
    {!ready&&!error&&<p role="status" className="map-notice">Loading marketplace map…</p>}
    {error&&<div role="alert" className="map-notice">{error} <button type="button" className="map-refresh" onClick={()=>setMapAttempt(value=>value+1)}>Retry map</button></div>}
    <div className="map-stage"><div ref={element} className="map-canvas" role="region" aria-label="Marketplace locations"/>{selectedMarker&&<DetailsCard marker={selectedMarker} onClose={()=>setSelected(null)}/>}</div>
    <div className="map-results" role="status">{visible.length} mapped {visible.length===1?'location':'locations'}{query?` matching “${query}”`:''}. <span>Updates every 15 seconds.</span></div>
    {!visible.length&&<p className="map-notice">{query?'No saved locations match this search. Try a city, property name or contractor name.':'No locations match the selected layers.'}</p>}
    {filters.includes('contractors')&&<section className="map-directory" aria-label="Contractor directory"><div className="map-directory__heading"><h4>Contractors</h4><span>{contractors.length} {query?'matching':'registered'}</span></div>
      <div className="map-directory__grid">{contractors.map(worker=><button type="button" className={`map-worker ${worker.id===selected?'map-worker--selected':''}`} key={worker.id} onClick={()=>focusWorker(worker)}><MarkerSymbol kind="contractor" config={data.config} offline={!worker.online}/><span><strong>{worker.title}</strong><span>{worker.details?.workCity??'Work location not set'}</span><small>{worker.detail}</small></span></button>)}</div>
      {!contractors.length&&<p>No contractors match this search.</p>}
    </section>}
    <p className="map-footnote">{data.notice}</p>
  </div>;
}

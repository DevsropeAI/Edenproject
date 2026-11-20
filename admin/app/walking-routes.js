'use client';
import {useEffect,useRef,useState} from 'react';
import {walkingPoints,walkingShifts} from './walking-actions';

export default function WalkingRoutes({mapRef,libraryRef,ready,contractors,config}){
  const [contractor,setContractor]=useState('');const [from,setFrom]=useState('');const [to,setTo]=useState('');
  const [shifts,setShifts]=useState([]);const [id,setId]=useState('');const [route,setRoute]=useState(null);
  const [error,setError]=useState('');const [loading,setLoading]=useState(false);const fit=useRef('');
  useEffect(()=>{let disposed=false;let busy=false;
    async function load(){if(busy)return;busy=true;setLoading(true);try{const r=await walkingShifts({contractor,from,to});if(!disposed){setShifts(r.shifts);setError('');}}catch(_){if(!disposed)setError('Could not load shifts. Retrying shortly.');}finally{busy=false;if(!disposed)setLoading(false);}}
    load();const timer=setInterval(load,15000);return()=>{disposed=true;clearInterval(timer);};
  },[contractor,from,to]);
  useEffect(()=>{setId('');setRoute(null);},[contractor,from,to]);
  useEffect(()=>{if(!id){setRoute(null);return;}let disposed=false;let busy=false;
    async function load(){if(busy)return;busy=true;try{const r=await walkingPoints(id);if(!disposed){setRoute(r);setError('');}}catch(_){if(!disposed)setError('Could not load route. Retrying shortly.');}finally{busy=false;}}
    load();const timer=setInterval(load,15000);return()=>{disposed=true;clearInterval(timer);};
  },[id]);
  useEffect(()=>{
    if(!ready||!route||!mapRef.current)return;
    const L=libraryRef.current,map=mapRef.current,layer=L.layerGroup().addTo(map),color=config.color;
    const segments=[];let segment=[];
    for(const p of route.points){if(p.gapBefore&&segment.length){segments.push(segment);segment=[];}segment.push([p.latitude,p.longitude]);}
    if(segment.length)segments.push(segment);
    for(const points of segments)if(points.length>1)L.polyline(points,{color,weight:config.weight,dashArray:config.dashArray}).addTo(layer);
    if(route.points.length){
      const first=route.points[0],last=route.points.at(-1);
      L.circleMarker([first.latitude,first.longitude],{color,fillColor:color,fillOpacity:1,radius:6}).addTo(layer).bindTooltip('Walking shift start');
      L.circleMarker([last.latitude,last.longitude],{color,fillColor:route.shift.status==='active'?color:'white',fillOpacity:1,radius:10,weight:3}).addTo(layer).bindTooltip(route.shift.status==='active'?'Last walking position':'Walking shift end');
      for(let i=1;i<route.points.length;i++)if(route.points[i].gapBefore)L.circleMarker([route.points[i].latitude,route.points[i].longitude],{color,radius:5,dashArray:'2 3',fillOpacity:0}).addTo(layer).bindTooltip('Tracking resumed after a gap');
      if(fit.current!==id){map.fitBounds(route.points.map(p=>[p.latitude,p.longitude]),{maxZoom:17,padding:[45,45]});fit.current=id;}
    }
    return()=>{if(map.hasLayer(layer))map.removeLayer(layer);};
  },[ready,route,id,mapRef,libraryRef,config]);
  const minutes=route?Math.max(0,Math.round(((route.shift.endedAt?Date.parse(route.shift.endedAt):Date.now())-Date.parse(route.shift.startedAt))/60000)):0;
  const gaps=route?.points.slice(1).filter(p=>p.gapBefore).length??0;
  const paused=route?.shift.status==='active'&&(!route.points.length||Date.now()-Date.parse(route.points.at(-1).recordedAt)>45000);
  return <section className="walking-routes" aria-label="Door-to-door walking routes" style={{'--walking-color':config.color}}>
    <div className="walking-route-controls">
      <label>Contractor<select value={contractor} onChange={e=>setContractor(e.target.value)}><option value="">All contractors</option>{contractors.map(c=><option key={c.id} value={c.id}>{c.title}</option>)}</select></label>
      <label>From (UTC)<input type="date" value={from} onChange={e=>setFrom(e.target.value)}/></label>
      <label>To (UTC)<input type="date" value={to} onChange={e=>setTo(e.target.value)}/></label>
      <label>Shift<select value={id} onChange={e=>setId(e.target.value)}><option value="">Select a walking shift</option>{shifts.map(s=><option key={s.id} value={s.id}>{contractors.find(c=>c.id===s.contractorId)?.title??'Contractor'} · {new Date(s.startedAt).toLocaleString()} · {s.status}</option>)}</select></label>
    </div>
    {loading&&<p role="status">Loading shifts…</p>}{error&&<p role="alert">{error}</p>}
    {!loading&&!shifts.length&&!error&&<p>No walking shifts match these filters.</p>}
    {route&&<p role="status">{(Number(route.shift.distanceM)/1000).toFixed(2)} km · {minutes} min · {gaps} tracking gaps · {paused?'Tracking paused':route.shift.status==='active'?'Active shift':'Ended shift'}</p>}
    <div className="walking-route-legend"><span className="walking-route-line"/> Walking route <span className="walking-route-start"/> Start <span className="walking-route-end"/> End / current position</div>
    <p className="map-search__hint">Updates every 15 seconds. Gaps remain disconnected; missing movement is never inferred.</p>
  </section>;
}

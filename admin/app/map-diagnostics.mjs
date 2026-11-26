const allowed = new Set(['origin','keyConfigured','domReady','width','height','markerCount','attempt','elapsedMs','mapLibraryReady','markerLibraryReady','usingDemoMapId','blockedHost','directive','code','name','message','stack']);
const redact = value => String(value)
  .replace(/AIza[\w-]+/g,'[REDACTED_KEY]')
  .replace(/([?&](?:key|api_key|token|secret|password)=)[^\s&#)]+/gi,'$1[REDACTED]')
  .replace(/(https?:\/\/[^\s?]+)\?[^\s)]*/g,'$1?[REDACTED_QUERY]')
  .slice(0,1800);

export function mapFailureDetails(error) {
  // Do not log arbitrary error messages: they can contain request bodies,
  // coordinates or user-entered text. Keep the error type/code and stack frames.
  return {
    name: /^\w{1,64}$/.test(error?.name??'') ? error.name : 'Error',
    code: /^[A-Z][A-Z0-9_]{0,63}$/.test(error?.code??'') ? error.code : 'MAPS_INIT_FAILURE',
    stack: typeof error?.stack==='string' ? redact(error.stack.split('\n').filter(line=>/^\s*at\s/.test(line)).slice(0,8).join('\n')) : '',
  };
}

export function mapDiagnostic(level,event,details={}) {
  const safe={};
  for(const [key,value] of Object.entries(details)) {
    if(!allowed.has(key))continue;
    if(typeof value==='string')safe[key]=redact(value);
    else if(typeof value==='number'||typeof value==='boolean')safe[key]=value;
  }
  const method=['info','warn','error'].includes(level)?level:'info';
  console[method](`[Eden Maps][admin][diagnostics-v1] ${event}`,safe);
}

export function watchMapBrowserFailures(onFailure) {
  const previous=window.gm_authFailure;
  const authFailure=()=>{
    const error=Object.assign(new Error('Google Maps authentication failed.'),{code:'MAPS_AUTH'});
    mapDiagnostic('error','google-auth-failure',{code:'MAPS_AUTH',origin:window.location?.origin??'',message:'Google rejected Maps authentication. Check its Console error, website restrictions, API activation and billing.'});
    onFailure(error);
    if(typeof previous==='function')try{previous();}catch(error){mapDiagnostic('error','previous-auth-handler-failed',mapFailureDetails(error));}
  };
  const csp=event=>{
    if(!/maps\.(googleapis|gstatic)\.com/.test(event.blockedURI??''))return;
    let blockedHost='';try{blockedHost=new URL(event.blockedURI).host;}catch{}
    mapDiagnostic('error','content-security-policy-blocked',{code:'MAPS_CSP',blockedHost,directive:event.effectiveDirective??''});
    onFailure(Object.assign(new Error('Maps was blocked by site security policy.'),{code:'MAPS_CSP'}));
  };
  window.gm_authFailure=authFailure;
  window.addEventListener('securitypolicyviolation',csp);
  return ()=>{window.removeEventListener('securitypolicyviolation',csp);if(window.gm_authFailure===authFailure)window.gm_authFailure=previous;};
}

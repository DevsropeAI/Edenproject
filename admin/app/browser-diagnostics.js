'use client';
import {useEffect} from 'react';
import {mapDiagnostic,mapFailureDetails} from './map-diagnostics.mjs';

export default function BrowserDiagnostics() {
  useEffect(()=>{
    mapDiagnostic('info','admin-client-ready',{origin:window.location.origin});
    const error=event=>mapDiagnostic('error','admin-unhandled-error',mapFailureDetails(event.error));
    const rejection=event=>mapDiagnostic('error','admin-unhandled-rejection',mapFailureDetails(event.reason));
    window.addEventListener('error',error);
    window.addEventListener('unhandledrejection',rejection);
    return ()=>{window.removeEventListener('error',error);window.removeEventListener('unhandledrejection',rejection);};
  },[]);
  return null;
}

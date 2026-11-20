'use server';
import {cookies} from 'next/headers';
import {revalidatePath} from 'next/cache';
import {sessionCookie,validSession} from '../admin-auth';
import {adminRequest} from './admin-api';
async function authorise(){if(!validSession((await cookies()).get(sessionCookie)?.value))throw Error('Admin sign-in required.');}
export async function setWalkingAccess(id,form){
  await authorise();if(!/^[a-f0-9]{64}$/.test(id))throw Error('Invalid contractor.');
  await adminRequest('/contractors/'+id+'/door-to-door',{method:'POST',body:JSON.stringify({enabled:form.get('enabled')==='true'})});revalidatePath('/');
}
export async function walkingShifts(filters){
  await authorise();const q=new URLSearchParams();
  for(const key of ['contractor','from','to'])if(typeof filters[key]==='string'&&filters[key])q.set(key,filters[key]);
  return adminRequest('/walking/shifts?'+q);
}
export async function walkingPoints(id){
  await authorise();if(!/^[a-f0-9-]{36}$/.test(id))throw Error('Invalid shift.');return adminRequest('/walking/shifts/'+id+'/points');
}

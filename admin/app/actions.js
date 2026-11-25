'use server';

import { redirect } from 'next/navigation';
import { cookies } from 'next/headers';
import { sessionCookie, validSession } from '../admin-auth';
import { adminRequest } from './admin-api';

export async function updateStatus(section, search, formData) {
  if (!validSession((await cookies()).get(sessionCookie)?.value)) {
    throw new Error('Admin sign-in required.');
  }
  const { type, id, status, price } = Object.fromEntries(formData);
  const formats = {
    accounts: /^[a-f0-9]{64}$/, support: /^[a-f0-9]{64}$/, orders: /^\d+$/,
    services: /^[A-Za-z][A-Za-z0-9]{0,19}$/, verification: /^[a-f0-9]{64}$/,
    payments: /^[a-f0-9-]{36}$/,
  };
  if (!Object.hasOwn(formats, type) || typeof id !== 'string' || !formats[type].test(id)) {
    throw new Error('Invalid record.');
  }
  const priceCents = type === 'services' ? moneyCents(price) : undefined;
  const query = new URLSearchParams({ section, search });
  try {
    await adminRequest('/' + type + '/' + id, { method: 'POST', body: JSON.stringify({ status, priceCents,
      ...(type==='services'?serviceFields(formData):{}) }) });
    query.set('result', 'saved');
  } catch (error) {
    console.error(error);
    query.set('result', 'error');
  }
  redirect('/?' + query);
}

export async function loadDocument(id, kind) {
  if (!validSession((await cookies()).get(sessionCookie)?.value)) {
    throw new Error('Admin sign-in required.');
  }
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id) || !['identification', 'insurance'].includes(kind)) {
    throw new Error('Invalid document.');
  }
  return adminRequest('/verification/' + id + '/' + kind);
}


function moneyCents(value) {
  if(typeof value!=='string'||!/^\d{1,5}(?:\.\d{1,2})?$/.test(value))throw new Error('Enter a valid price.');
  const [whole,fraction='']=value.split('.');
  return Number(whole)*100+Number(fraction.padEnd(2,'0'));
}
function serviceFields(form) {
  return {title:form.get('title')};
}
export async function createService(form) {
  if(!validSession((await cookies()).get(sessionCookie)?.value))throw new Error('Admin sign-in required.');
  const query=new URLSearchParams({section:'Services'});
  try {
    await adminRequest('/services',{method:'POST',body:JSON.stringify({...serviceFields(form),priceCents:moneyCents(form.get('price')),status:form.get('status')})});
    query.set('result','saved');
  } catch {query.set('result','error');}
  redirect('/?'+query);
}

export async function dispatchJob(id, section, search, formData) {
  if (!validSession((await cookies()).get(sessionCookie)?.value)) throw new Error('Admin sign-in required.');
  if (!/^\d+$/.test(id)) throw new Error('Invalid job.');
  const query=new URLSearchParams({section,search});
  try {
    await adminRequest('/dispatch/'+id,{method:'POST',body:JSON.stringify({action:'assign',contractorId:formData.get('contractorId'),note:formData.get('note')})});
    query.set('result','saved');
  }catch {query.set('result','error');}
  redirect('/?'+query);
}

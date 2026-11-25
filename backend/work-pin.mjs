export function validateWorkPin(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      !Number.isFinite(input.latitude) || !Number.isFinite(input.longitude) ||
      Math.abs(input.latitude)>90 || Math.abs(input.longitude)>180) {
    throw Object.assign(new Error('Choose a valid work-location pin.'),{status:400});
  }
  return {latitude:input.latitude,longitude:input.longitude};
}

export async function saveWorkPin(run,userId,pin) {
  const data=JSON.stringify({workPin:validateWorkPin(pin)});
  await run(`INSERT INTO preferences (user_id,details) VALUES (?,?)
    ON DUPLICATE KEY UPDATE details=JSON_MERGE_PATCH(details,?)`,userId,data,data);
}

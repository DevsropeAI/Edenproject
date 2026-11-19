const fail = message => { throw Object.assign(new Error(message), { status: 400 }); };
const string = (value, limit, required = false) => {
  if (typeof value !== 'string' || value.length > limit || (required && !value.trim())) fail('Check the address fields.');
  return value.trim();
};

export function structuredAddress(body, existing = {}) {
  if (body.structuredAddress == null) return existing;
  const input = body.structuredAddress;
  if (typeof input !== 'object' || Array.isArray(input)) fail('Check the address fields.');
  const fields = {
    street: string(input.street ?? '', 150, true),
    city: string(input.city ?? '', 150, true),
    state: string(input.state ?? '', 150),
    postalCode: string(input.postalCode ?? '', 30),
    country: string(input.country ?? '', 100, true),
  };
  if (fields.street.includes(',') || fields.city.includes(',')) fail('Enter street and city in their separate fields.');
  return fields;
}

export function propertyMeasurements(input, existing = {}) {
  if (input == null) return existing;
  if (typeof input !== 'object' || Array.isArray(input)) fail('Check the property measurements.');
  const result = {};
  for (const [field, choices, defaultValue] of [
    ['driveway', ['small', 'medium', 'large'], 'medium'],
    ['walkway', ['none', 'short', 'long'], 'none'],
  ]) {
    const value = input[field] ?? defaultValue;
    if (!choices.includes(value)) fail('Choose valid property measurements.');
    result[field] = value;
  }
  for (const field of ['frontYard', 'backyard']) {
    const value = input[field] ?? false;
    if (typeof value !== 'boolean') fail('Choose valid yard details.');
    result[field] = value;
    result[field + 'Size'] = string(input[field + 'Size'] ?? '', 50);
  }
  return result;
}

export function createAddressStore(run, first) {
  return {
    async city(input) {
      if (input == null) return null;
      if (typeof input !== 'object' || Array.isArray(input)) fail('Choose a valid city.');
      const name = string(input.city ?? input.name ?? '', 150, true);
      const state = string(input.state ?? '', 150);
      const country = string(input.country ?? '', 100, true);
      const lat = input.latitude ?? null, lng = input.longitude ?? null;
      if ((lat !== null || lng !== null) && (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180)) fail('Choose valid city coordinates.');
      await run('INSERT IGNORE INTO cities (name, state, country, latitude, longitude) VALUES (?, ?, ?, ?, ?)', name, state, country, lat, lng);
      const city = await first('SELECT id, active FROM cities WHERE name = ? AND state = ? AND country = ?', name, state, country);
      if (!city?.active) fail('This city is unavailable.');
      if (lat !== null && lng !== null) {
        await run(
          'UPDATE cities SET latitude = COALESCE(latitude, ?), longitude = COALESCE(longitude, ?) WHERE id = ?',
          lat, lng, city.id,
        );
      }
      return city.id;
    },
  };
}

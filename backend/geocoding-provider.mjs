const unavailable = message => { throw Object.assign(new Error(message), { status: 503 }); };

export class GeocodingProvider {
  async search() { unavailable('Address search is unavailable. Enter the address manually.'); }
  async autocomplete() { unavailable('Address suggestions are unavailable. Use Search or enter the address manually.'); }
  async reverse() { unavailable('Address lookup is unavailable. Enter the address manually.'); }
  async place() { unavailable('Address details are unavailable. Enter the address manually.'); }
}

import { openDatabase } from './db.mjs';
import { configureDatabase } from './local-setup.mjs';

const db = await openDatabase(await configureDatabase());
await db.end();
console.log('Eden database is ready.');

#!/usr/bin/env node
/*
 * Read-only spike against the live Humanitix API. Confirms the two facts the
 * connector's incremental sync depends on and that the spec can't answer:
 *   1. Does `since` filter on created or last-modified time?
 *   2. How does pagination behave (page-based, stable)?
 *
 * Usage:  HUMANITIX_API_KEY=your-key node scripts/spike.mjs
 *
 * Your key never leaves your machine; this issues only GET requests. Requires
 * Node 18+ (global fetch).
 */
const KEY = process.env.HUMANITIX_API_KEY;
const BASE = process.env.HUMANITIX_BASE || 'https://api.humanitix.com';

if (!KEY) {
  console.error('Set HUMANITIX_API_KEY, e.g. HUMANITIX_API_KEY=xxxx node scripts/spike.mjs');
  process.exit(1);
}

const ids = (arr) => (arr || []).map((e) => e._id);

async function get(path) {
  const res = await fetch(BASE + path, {
    headers: { 'x-api-key': KEY, Accept: 'application/json' }
  });
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { status: res.status, body, retryAfter: res.headers.get('retry-after') };
}

(async () => {
  console.log('== Humanitix API spike ==');
  console.log('Base:', BASE, '\n');

  const p1 = await get('/v1/events?page=1&pageSize=3');
  console.log('GET /v1/events?page=1&pageSize=3 ->', p1.status);
  if (p1.status !== 200) {
    console.log('Body:', p1.body);
    console.log('\nA 401/403 means the key is wrong. Fix and retry.');
    process.exit(1);
  }
  const { total, page, pageSize, events } = p1.body;
  console.log(`  total=${total} page=${page} pageSize=${pageSize} returned=${events ? events.length : 0}`);
  if (events && events.length) {
    const e = events[0];
    console.log(`  sample _id=${e._id} createdAt=${e.createdAt} updatedAt=${e.updatedAt}`);
  }

  const p2 = await get('/v1/events?page=2&pageSize=3');
  console.log('GET /v1/events?page=2&pageSize=3 ->', p2.status, 'returned=', p2.body.events ? p2.body.events.length : 0);
  const overlap = ids(p1.body.events).filter((id) => ids(p2.body.events).includes(id));
  console.log('  page1/page2 id overlap:', overlap.length, overlap.length ? '(!) page-based pagination may be unstable' : '(clean, page-based)');

  if (events && events.length) {
    const evt = events[0];
    const justAfter = new Date(new Date(evt.updatedAt).getTime() + 1000).toISOString();
    const s = await get('/v1/events?page=1&pageSize=50&since=' + encodeURIComponent(justAfter));
    const stillThere = ids(s.body.events).includes(evt._id);
    console.log('\n`since` semantics test using since=' + justAfter);
    console.log('  is the event still returned after its own updatedAt?', stillThere);
    console.log(
      '  =>',
      stillThere
        ? 'since does NOT filter on updatedAt (likely createdAt). Set Since_Mode__c = FullPull, or confirm with Humanitix support.'
        : 'since appears to filter on last-modified time. Keep Since_Mode__c = Modified (the default).'
    );
  }

  console.log('\nDone. Record these two findings in docs/CONFIGURATION.md.');
})().catch((e) => {
  console.error('Spike failed:', e.message);
  process.exit(1);
});

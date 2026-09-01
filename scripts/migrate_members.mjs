/**
 * Backfills companies/{companyId}/members/{uid} from the companyMemberships
 * already recorded on each user doc.
 *
 * WHY: membership used to be proved by a field the client writes about itself,
 * so it authorised itself. Member docs cannot be forged that way — the rules
 * require a join code that really maps to the company, or the company's own
 * creator. Until a user has one, they cannot switch workspaces (their current
 * workspace is unaffected).
 *
 * This is the REST variant of scripts/migrate_members.js: it signs a JWT with
 * Node's built-in crypto and talks to the Firestore REST API, so it needs no
 * npm install. Prefer it unless you already have firebase-admin available.
 *
 * Usage — dry run first, it writes nothing without --apply:
 *
 *   SA_KEY=/path/to/serviceAccount.json node scripts/migrate_members.mjs
 *   SA_KEY=/path/to/serviceAccount.json node scripts/migrate_members.mjs --apply
 *
 * Keep the key file OUTSIDE this repo.
 */
import fs from 'node:fs';
import crypto from 'node:crypto';

const KEY_PATH = process.env.SA_KEY;
const APPLY = process.argv.includes('--apply');
const sa = JSON.parse(fs.readFileSync(KEY_PATH, 'utf8'));
const PROJECT = sa.project_id;
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const b64 = (o) =>
  Buffer.from(typeof o === 'string' ? o : JSON.stringify(o))
    .toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64(claim)}`;
  const sig = crypto
    .createSign('RSA-SHA256')
    .update(unsigned)
    .sign(sa.private_key)
    .toString('base64url');

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${sig}`,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`Token failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

const TOKEN = await accessToken();
const auth = { Authorization: `Bearer ${TOKEN}` };

async function api(path, init = {}) {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { ...auth, 'Content-Type': 'application/json', ...(init.headers || {}) },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${res.status} ${path}: ${await res.text()}`);
  return res.json();
}

/** Firestore REST typed value -> plain JS. */
function decode(v) {
  if (v == null) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  return null;
}
const decodeFields = (f) =>
  Object.fromEntries(Object.entries(f).map(([k, v]) => [k, decode(v)]));

console.log(APPLY ? 'APPLYING changes' : 'DRY RUN (pass --apply to write)');
console.log(`Project: ${PROJECT}\n`);

// ---- Read every user, paging through the collection ------------------------
const users = [];
let pageToken;
do {
  const q = new URLSearchParams({ pageSize: '300' });
  if (pageToken) q.set('pageToken', pageToken);
  const page = await api(`/users?${q}`);
  for (const d of page?.documents || []) {
    users.push({ id: d.name.split('/').pop(), data: decodeFields(d.fields || {}) });
  }
  pageToken = page?.nextPageToken;
} while (pageToken);

console.log(`Scanned ${users.length} user doc(s)\n`);

const companyCache = new Map();
async function companyExists(id) {
  if (companyCache.has(id)) return companyCache.get(id);
  const doc = await api(`/companies/${id}`);
  companyCache.set(id, doc != null);
  return doc != null;
}

let planned = 0, written = 0, skipped = 0;
const orphans = [];

for (const { id: uid, data } of users) {
  const entries = new Map();
  const memberships = Array.isArray(data.companyMemberships)
    ? data.companyMemberships
    : [];
  for (const m of memberships) {
    if (m && typeof m.companyId === 'string' && m.companyId) {
      entries.set(m.companyId, { role: m.role || 'staff', roleId: m.roleId || '' });
    }
  }
  // Older docs predate the memberships list, so fall back to the active company.
  if (typeof data.companyId === 'string' && data.companyId && !entries.has(data.companyId)) {
    entries.set(data.companyId, { role: data.role || 'staff', roleId: data.roleId || '' });
  }

  for (const [companyId, { role, roleId }] of entries) {
    if (!(await companyExists(companyId))) {
      orphans.push(`${uid} -> ${companyId}`);
      continue;
    }
    const existing = await api(`/companies/${companyId}/members/${uid}`);
    if (existing) { skipped++; continue; }

    planned++;
    if (!APPLY) {
      console.log(`  would create members/${uid} in ${companyId} (role=${role})`);
      continue;
    }
    // updateMask with no field paths on a missing doc creates it.
    await api(`/companies/${companyId}/members/${uid}`, {
      method: 'PATCH',
      body: JSON.stringify({
        fields: {
          uid: { stringValue: uid },
          role: { stringValue: role },
          roleId: { stringValue: roleId },
          email: { stringValue: data.email || '' },
          name: { stringValue: data.name || '' },
          migrated: { booleanValue: true },
          joinedAt: { timestampValue: data.createdAt || new Date().toISOString() },
        },
      }),
    });
    written++;
    console.log(`  created members/${uid} in ${companyId} (role=${role})`);
  }
}

console.log('');
console.log(`  to create : ${planned}`);
console.log(`  written   : ${written}`);
console.log(`  already ok: ${skipped}`);
if (orphans.length) {
  console.log(`  orphaned memberships (company doc missing): ${orphans.length}`);
  for (const o of orphans) console.log(`    ${o}`);
}
if (!APPLY && planned > 0) console.log('\nRe-run with --apply to write these.');

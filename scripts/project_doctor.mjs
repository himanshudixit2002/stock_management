/**
 * Audits a Firebase project against the schema `firestore.rules` actually
 * enforces, and reports every gap that stops screens loading.
 *
 * WHY: the rules are the real schema. A screen does not fail because a field
 * is "missing" in the abstract — it fails because `canReadCompanyDoc` or
 * `hasPermission` returned false, and those read specific documents:
 *
 *   users/{uid}                        .role, .roleId, .companyId
 *   companies/{cid}/roles/{roleId}     .permissions[<key>] == true
 *   companies/{cid}/members/{uid}      proves membership for workspace switching
 *   superAdmins/{uid}                  the whole super-admin area
 *
 * A brand-new project is the worst case: nothing bootstraps `superAdmins`,
 * because /superAdmins is `allow write: if false` for EVERY client including
 * super admins themselves. And /plans, /publicConfig and /metadata are all
 * `write: isSuperAdmin()`, so until one exists none of them can be seeded
 * either. That is a chicken-and-egg only a service account can break.
 *
 * Reads only, unless --apply. The repairs it can make are the ones the app
 * itself would have made: seeding a company's default roles, and backfilling
 * member docs. Granting super admin is deliberately NOT one of them — use
 * scripts/grant_super_admin.mjs, so that stays a separate, explicit act.
 *
 * Usage:
 *   SA_KEY=/path/to/serviceAccount.json node scripts/project_doctor.mjs
 *   SA_KEY=/path/to/serviceAccount.json node scripts/project_doctor.mjs --apply
 *
 * Keep the key file OUTSIDE this repo.
 */
import fs from 'node:fs';
import crypto from 'node:crypto';

const KEY_PATH = process.env.SA_KEY;
if (!KEY_PATH) {
  console.error('Set SA_KEY to the path of a service account JSON file.');
  console.error('Firebase console > Project settings > Service accounts >');
  console.error('  Generate new private key. Save it OUTSIDE this repo.');
  process.exit(1);
}
const APPLY = process.argv.includes('--apply');
const sa = JSON.parse(fs.readFileSync(KEY_PATH, 'utf8'));
const PROJECT = sa.project_id;
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// These must match lib/models/role_model.dart.
const DEFAULT_ROLE_IDS = ['owner', 'admin', 'manager', 'staff', 'viewer'];
// These must match lib/providers/settings_provider.dart. Empty lists are what
// made Bulk Stock In and Bulk Edit impossible to complete.
const SETTINGS_LISTS = ['locations', 'companies', 'sizes'];

const b64 = (o) =>
  Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

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
  const sig = crypto.createSign('RSA-SHA256').update(unsigned)
    .sign(sa.private_key).toString('base64url');
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

async function listAll(path) {
  const out = [];
  let pageToken;
  do {
    const q = new URLSearchParams({ pageSize: '300' });
    if (pageToken) q.set('pageToken', pageToken);
    const page = await api(`${path}?${q}`);
    for (const d of page?.documents || []) {
      out.push({ id: d.name.split('/').pop(), data: decodeFields(d.fields || {}) });
    }
    pageToken = page?.nextPageToken;
  } while (pageToken);
  return out;
}

// --- findings ---------------------------------------------------------------
const BLOCKER = 'BLOCKER', WARN = 'WARN';
const findings = [];
const note = (level, what, why, fix) => findings.push({ level, what, why, fix });

console.log(`Project : ${PROJECT}`);
console.log(`Mode    : ${APPLY ? 'APPLY (will write)' : 'read-only audit'}\n`);

// 1. Super admin -------------------------------------------------------------
const superAdmins = await listAll('/superAdmins');
if (superAdmins.length === 0) {
  note(BLOCKER, 'No superAdmins/{uid} document exists',
    'isSuperAdmin() is false for everyone, so the entire super-admin area ' +
    'cannot load, and /plans, /publicConfig and /metadata are unwritable ' +
    '(all three are `write: isSuperAdmin()`).',
    `SA_KEY=$SA_KEY node scripts/grant_super_admin.mjs <your-email>`);
} else {
  console.log(`superAdmins : ${superAdmins.length} (${superAdmins.map(s => s.id).join(', ')})`);
}

// 2. Plan catalog ------------------------------------------------------------
const plans = await listAll('/plans');
if (plans.length === 0) {
  note(WARN, 'The /plans collection is empty',
    'Reads fail open to PlanCatalog.seedDefaults, so this does not block a ' +
    'screen — but pricing shown in-app is the hardcoded fallback, and it ' +
    'cannot be edited until a super admin exists.',
    'Grant super admin first, then seed from the in-app super-admin screen.');
} else {
  console.log(`plans       : ${plans.length}`);
}

// 3. Users -------------------------------------------------------------------
const users = await listAll('/users');
console.log(`users       : ${users.length}`);
for (const u of users) {
  const d = u.data;
  const who = `${d.email || u.id}`;
  if (!d.companyId) {
    note(BLOCKER, `users/${u.id} (${who}) has no companyId`,
      'canReadCompanyDoc() needs belongsToCompany(companyId); with no ' +
      'companyId every company-scoped read is denied, so no screen loads.',
      'Set companyId on the user doc, or have them re-run onboarding.');
    continue;
  }
  const isAdminish = d.role === 'admin' || d.role === 'owner';
  if (!isAdminish && !d.roleId && !d.permissions) {
    note(BLOCKER, `users/${u.id} (${who}) has role='${d.role}' and no roleId`,
      'hasPermission() short-circuits only for admin/owner. Without a roleId ' +
      'pointing at a real role doc, and no inline permissions map, every ' +
      'permission resolves false and every gated screen is blocked.',
      'Run the in-app RBAC migration, or set roleId to one of: ' +
      DEFAULT_ROLE_IDS.join(', '));
  }
}

// 4. Companies ---------------------------------------------------------------
const companies = await listAll('/companies');
console.log(`companies   : ${companies.length}\n`);

let repaired = 0;
for (const c of companies) {
  const label = `${c.data.companyName || c.id} (${c.id})`;

  // 4a. Roles subcollection.
  const roles = await listAll(`/companies/${c.id}/roles`);
  const haveRoles = new Set(roles.map(r => r.id));
  const missingRoles = DEFAULT_ROLE_IDS.filter(r => !haveRoles.has(r));
  if (roles.length === 0) {
    note(BLOCKER, `${label}: no roles sub-collection`,
      'hasPermission() does an exists() on companies/{cid}/roles/{roleId}. ' +
      'With none, every non-admin user is denied everything.',
      'Seeded automatically at company creation; for an existing company the ' +
      'app calls ensureRolesSeeded(). Re-open the app as owner to trigger it.');
  } else if (missingRoles.length) {
    note(WARN, `${label}: missing default roles [${missingRoles.join(', ')}]`,
      'Any user whose roleId is one of these resolves to no permissions.',
      'ensureRolesSeeded() only seeds when the collection is EMPTY, so a ' +
      'partial set is never repaired by the app. Re-create them by hand.');
  }

  // 4b. Members subcollection vs the memberships users claim.
  const members = await listAll(`/companies/${c.id}/members`);
  const haveMembers = new Set(members.map(m => m.id));
  const claim = users.filter(u =>
    u.data.companyId === c.id ||
    (Array.isArray(u.data.companyMemberships) &&
     u.data.companyMemberships.some(m => (m && m.companyId) === c.id)));
  for (const u of claim) {
    if (haveMembers.has(u.id)) continue;
    note(WARN, `${label}: no members/${u.id} for ${u.data.email || u.id}`,
      'hasMembershipForCompany() is what allows switching INTO this ' +
      'workspace. Their current workspace still works; switching does not. ' +
      'Note the app writes this doc best-effort and swallows failures.',
      'scripts/migrate_members.mjs --apply, or --apply here.');
    if (APPLY) {
      await api(`/companies/${c.id}/members?documentId=${u.id}`, {
        method: 'POST',
        body: JSON.stringify({ fields: {
          uid: { stringValue: u.id },
          role: { stringValue: u.data.role || 'staff' },
          roleId: { stringValue: u.data.roleId || 'staff' },
          email: { stringValue: u.data.email || '' },
          name: { stringValue: u.data.name || '' },
          joinedAt: { timestampValue: new Date().toISOString() },
        }}),
      });
      repaired++;
    }
  }

  // 4c. Settings lists — empty ones make whole workflows uncompletable.
  // These live as a `settings` MAP on the company doc itself, not in a
  // sub-collection; see SettingsProvider, which reads data['settings'].
  const sd = c.data.settings || {};
  const emptyLists = SETTINGS_LISTS.filter(k => !(sd[k] || []).length);
  if (emptyLists.length) {
    note(WARN, `${label}: settings lists empty [${emptyLists.join(', ')}]`,
      'Every stock screen requires a location, and Bulk Edit cannot set a ' +
      'company or sub-category that does not exist. The screens now say so ' +
      'and deep-link to the editor instead of failing on submit.',
      'Settings > Catalog, or the "Add locations" button on the screen.');
  }
}

// --- report -----------------------------------------------------------------
const blockers = findings.filter(f => f.level === BLOCKER);
const warns = findings.filter(f => f.level === WARN);

for (const group of [blockers, warns]) {
  for (const f of group) {
    console.log(`[${f.level}] ${f.what}`);
    console.log(`   why : ${f.why}`);
    console.log(`   fix : ${f.fix}\n`);
  }
}

console.log('─'.repeat(70));
console.log(`${blockers.length} blocker(s), ${warns.length} warning(s)`);
if (APPLY) console.log(`${repaired} document(s) written`);
else if (findings.length) console.log('Read-only. Pass --apply to repair what is repairable.');
if (!findings.length) console.log('Nothing to report — schema matches what the rules require.');
process.exit(blockers.length ? 1 : 0);

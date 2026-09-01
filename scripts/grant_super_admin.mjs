/**
 * Grants or revokes platform super admin by creating/deleting the
 * `superAdmins/{uid}` doc that firestore.rules tests for.
 *
 * Nothing in the app can do this — /superAdmins is `allow write: if false` for
 * every client, including existing super admins — so it is deliberately a
 * console or service-account action.
 *
 * Signs a JWT with Node's built-in crypto, so no npm install is needed.
 *
 * Usage:
 *   SA_KEY=/path/to/serviceAccount.json node scripts/grant_super_admin.mjs <email>
 *   SA_KEY=/path/to/serviceAccount.json node scripts/grant_super_admin.mjs <email> --revoke
 *   SA_KEY=/path/to/serviceAccount.json node scripts/grant_super_admin.mjs --list
 *
 * Keep the key file OUTSIDE this repo.
 */
import fs from 'node:fs';
import crypto from 'node:crypto';

const KEY_PATH = process.env.SA_KEY;
if (!KEY_PATH) {
  console.error('Set SA_KEY to the path of a service account JSON file.');
  process.exit(1);
}
const sa = JSON.parse(fs.readFileSync(KEY_PATH, 'utf8'));
const PROJECT = sa.project_id;
const FS_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const args = process.argv.slice(2);
const LIST = args.includes('--list');
const REVOKE = args.includes('--revoke');
const email = args.find((a) => !a.startsWith('--'));

if (!LIST && !email) {
  console.error('Pass an email address, or --list.');
  process.exit(1);
}

const b64 = (o) =>
  Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: [
      'https://www.googleapis.com/auth/datastore',
      'https://www.googleapis.com/auth/identitytoolkit',
    ].join(' '),
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

if (LIST) {
  const res = await fetch(`${FS_BASE}/superAdmins?pageSize=100`, { headers: auth });
  const data = await res.json();
  const docs = data.documents || [];
  if (!docs.length) {
    console.log('No super admins.');
  } else {
    console.log(`${docs.length} super admin(s):`);
    for (const d of docs) {
      const uid = d.name.split('/').pop();
      const note = d.fields?.email?.stringValue || d.fields?.note?.stringValue || '';
      console.log(`  ${uid}  ${note}`);
    }
  }
  process.exit(0);
}

// Resolve the uid from the email — never from anything the caller types.
const lookup = await fetch(
  `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:lookup`,
  {
    method: 'POST',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: [email] }),
  },
);
const found = await lookup.json();
if (!found.users || !found.users.length) {
  console.error(`No Firebase Auth user with email ${email}.`);
  console.error('Create the account first (app signup, or Authentication in the console).');
  process.exit(2);
}
const uid = found.users[0].localId;

const docUrl = `${FS_BASE}/superAdmins/${uid}`;

if (REVOKE) {
  const res = await fetch(docUrl, { method: 'DELETE', headers: auth });
  if (!res.ok) {
    console.error(`Revoke failed: ${res.status} ${await res.text()}`);
    process.exit(1);
  }
  console.log(`Revoked super admin from ${email} (${uid}).`);
  console.log('Takes effect on their next request; no sign-out needed.');
  process.exit(0);
}

const res = await fetch(docUrl, {
  method: 'PATCH',
  headers: { ...auth, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    fields: {
      email: { stringValue: email },
      grantedAt: { timestampValue: new Date().toISOString() },
      note: { stringValue: 'granted via scripts/grant_super_admin.mjs' },
    },
  }),
});
if (!res.ok) {
  console.error(`Grant failed: ${res.status} ${await res.text()}`);
  process.exit(1);
}
console.log(`Granted super admin to ${email} (${uid}).`);
console.log('They will land on the super admin dashboard on next app load.');

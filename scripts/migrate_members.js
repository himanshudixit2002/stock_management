#!/usr/bin/env node
/**
 * Backfills companies/{companyId}/members/{uid} from the companyMemberships
 * already recorded on each user doc.
 *
 * WHY: membership is currently proved by a field the client writes about
 * itself, so it authorises itself — append a membership for any workspace,
 * switch companyId to it, and the security rules let you in. Member docs
 * cannot be forged that way. This script establishes them for existing users
 * so the rules can be switched over without locking anybody out.
 *
 * Run this AFTER deploying the rules that define the members subcollection and
 * AFTER shipping the client build that writes member docs, and BEFORE changing
 * belongsToCompany() to read from members.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
 *     node scripts/migrate_members.js [--apply]
 *
 * Without --apply it is a dry run and writes nothing.
 */
const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');

admin.initializeApp();
const db = admin.firestore();

async function main() {
  console.log(APPLY ? 'APPLYING changes' : 'DRY RUN (pass --apply to write)');

  const users = await db.collection('users').get();
  console.log(`Scanning ${users.size} user doc(s)...`);

  let planned = 0;
  let skipped = 0;
  let written = 0;
  const missingCompany = [];

  for (const doc of users.docs) {
    const data = doc.data() || {};
    const uid = doc.id;

    // Every workspace this user is recorded against: the memberships list plus
    // their currently-active companyId (older docs predate the list).
    const memberships = Array.isArray(data.companyMemberships)
      ? data.companyMemberships
      : [];
    const entries = new Map();
    for (const m of memberships) {
      if (m && typeof m.companyId === 'string' && m.companyId) {
        entries.set(m.companyId, {
          role: m.role || 'staff',
          roleId: m.roleId || '',
        });
      }
    }
    if (typeof data.companyId === 'string' && data.companyId && !entries.has(data.companyId)) {
      entries.set(data.companyId, {
        role: data.role || 'staff',
        roleId: data.roleId || '',
      });
    }

    for (const [companyId, { role, roleId }] of entries) {
      const companySnap = await db.collection('companies').doc(companyId).get();
      if (!companySnap.exists) {
        missingCompany.push(`${uid} -> ${companyId}`);
        continue;
      }

      const ref = db
        .collection('companies')
        .doc(companyId)
        .collection('members')
        .doc(uid);
      const existing = await ref.get();
      if (existing.exists) {
        skipped++;
        continue;
      }

      planned++;
      if (APPLY) {
        await ref.set({
          uid,
          role,
          roleId,
          email: data.email || '',
          name: data.name || '',
          migrated: true,
          joinedAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        });
        written++;
      } else {
        console.log(`  would create members/${uid} in ${companyId} (role=${role})`);
      }
    }
  }

  console.log('');
  console.log(`  to create : ${planned}`);
  console.log(`  written   : ${written}`);
  console.log(`  already ok: ${skipped}`);
  if (missingCompany.length) {
    console.log(`  orphaned memberships (company doc missing): ${missingCompany.length}`);
    for (const m of missingCompany) console.log(`    ${m}`);
  }
  if (!APPLY && planned > 0) {
    console.log('\nRe-run with --apply to write these.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Migration failed:', err);
    process.exit(1);
  });

import fs from 'fs';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, collection, getDocs, deleteDoc } from 'firebase/firestore';

const RULES = new URL('../../firestore.rules', import.meta.url).pathname;
const env = await initializeTestEnvironment({
  projectId: 'rules-test',
  firestore: { rules: fs.readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8080 },
});

// Re-seeded before EVERY test, so one test's write can never change another's
// outcome (an earlier version of this suite gave false passes that way).
async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db,'companies/companyA'),{companyName:'A',adminUid:'ownerA'});
    await setDoc(doc(db,'companies/companyB'),{companyName:'B',adminUid:'ownerB'});
    await setDoc(doc(db,'companies/companyC'),{companyName:'C',adminUid:'founder'});
    await setDoc(doc(db,'joinCodeIndex/ABC123'),{companyId:'companyA',companyName:'A'});
    await setDoc(doc(db,'users/ownerA'),{uid:'ownerA',email:'o@a.com',role:'admin',roleId:'owner',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'}]});
    await setDoc(doc(db,'users/staffA'),{uid:'staffA',email:'s@a.com',role:'staff',roleId:'staff',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'}]});
    // A staff user who has ALSO forged a membership for companyB — the exact
    // takeover attempt the rules must stop.
    await setDoc(doc(db,'users/mallory'),{uid:'mallory',email:'m@a.com',role:'staff',roleId:'staff',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'},{companyId:'companyB'}]});
    await setDoc(doc(db,'companies/companyA/invites/i1'),{code:'INV001',companyId:'companyA',companyName:'A'});
    await setDoc(doc(db,'companies/companyA/products/p1'),{name:'Widget',quantity:5});
    await setDoc(doc(db,'companies/companyB/products/p9'),{name:'Secret',quantity:9});
    await setDoc(doc(db,'companies/companyA/notifications/n1'),{title:'Low stock',isRead:false});
    // staffA has a migrated member doc for companyA only.
    await setDoc(doc(db,'companies/companyA/members/staffA'),{uid:'staffA',role:'staff'});
    // A super admin, and a suspended workspace with a member and some data.
    await setDoc(doc(db,'superAdmins/root'),{note:'founder'});
    await setDoc(doc(db,'companies/companyS'),{companyName:'Suspended',adminUid:'ownerS',status:'suspended'});
    await setDoc(doc(db,'users/staffS'),{uid:'staffS',email:'s@s.com',role:'admin',roleId:'admin',companyId:'companyS',permissions:{},companyMemberships:[{companyId:'companyS'}]});
    await setDoc(doc(db,'companies/companyS/products/p1'),{name:'Frozen',quantity:1});
    await setDoc(doc(db,'users/ownerB'),{uid:'ownerB',email:'o@b.com',role:'admin',roleId:'admin',companyId:'companyB',permissions:{},companyMemberships:[{companyId:'companyB'}]});
    await setDoc(doc(db,'metadata/app'),{firstUserCreated:true});
  });
}

let pass=0, fail=0;
async function check(name, fn) {
  await seed();
  try { await fn(); console.log(`  PASS  ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${String(e.message).split('\n')[0]}`); fail++; }
}
const as = (uid) => env.authenticatedContext(uid).firestore();

console.log('\n--- ESCALATION MUST FAIL ---');
await check('staff cannot make themselves admin', () =>
  assertFails(updateDoc(doc(as('staffA'),'users/staffA'),{role:'admin'})));
await check('staff cannot make themselves owner', () =>
  assertFails(updateDoc(doc(as('staffA'),'users/staffA'),{role:'owner',roleId:'owner'})));
await check('staff cannot grant themselves permissions', () =>
  assertFails(updateDoc(doc(as('staffA'),'users/staffA'),{permissions:{canManageUsers:true}})));
await check('forged membership does not allow switching workspace', () =>
  assertFails(updateDoc(doc(as('mallory'),'users/mallory'),{companyId:'companyB'})));
await check('cannot switch to a workspace with no member doc', () =>
  assertFails(updateDoc(doc(as('staffA'),'users/staffA'),{companyId:'companyB'})));
await check('new signup cannot self-create as admin elsewhere', () =>
  assertFails(setDoc(doc(as('x'),'users/x'),{uid:'x',role:'admin',roleId:'owner',companyId:'companyA',permissions:{}})));
await check('new signup cannot self-create with permission overrides', () =>
  assertFails(setDoc(doc(as('x'),'users/x'),{uid:'x',role:'staff',companyId:'companyA',permissions:{canManageUsers:true}})));
await check('outsider cannot read another companys products', () =>
  assertFails(getDoc(doc(as('x'),'companies/companyA/products/p1'))));
await check('staff cannot read a different companys products', () =>
  assertFails(getDoc(doc(as('staffA'),'companies/companyB/products/p9'))));
await check('outsider cannot list another companys invites', () =>
  assertFails(getDocs(collection(as('x'),'companies/companyA/invites'))));
await check('staff cannot forge an audit log as another user', () =>
  assertFails(setDoc(doc(as('staffA'),'companies/companyA/auditLogs/a1'),{userId:'ownerA',action:'stock_in'})));
await check('member doc rejects a bogus join code', () =>
  assertFails(setDoc(doc(as('x'),'companies/companyA/members/x'),{uid:'x',role:'staff',joinCode:'NOPE'})));
await check('member doc cannot self-claim admin', () =>
  assertFails(setDoc(doc(as('x'),'companies/companyA/members/x'),{uid:'x',role:'admin',joinCode:'ABC123'})));
await check('join code for A cannot mint a member doc in B', () =>
  assertFails(setDoc(doc(as('x'),'companies/companyB/members/x'),{uid:'x',role:'staff',joinCode:'ABC123'})));

console.log('\n--- LEGITIMATE FLOWS MUST WORK ---');
await check('workspace creator self-creates their admin user doc', () =>
  assertSucceeds(setDoc(doc(as('founder'),'users/founder'),{uid:'founder',email:'f@c.com',role:'admin',roleId:'owner',companyId:'companyC',permissions:{},companyMemberships:[{companyId:'companyC'}]})));
await check('normal signup self-creates as staff', () =>
  assertSucceeds(setDoc(doc(as('newbie'),'users/newbie'),{uid:'newbie',email:'n@a.com',role:'staff',roleId:'staff',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'}]})));
await check('admin provisions a teammate with any role', () =>
  assertSucceeds(setDoc(doc(as('ownerA'),'users/newAdmin'),{uid:'newAdmin',email:'na@a.com',role:'admin',roleId:'admin',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'}]})));
await check('admin promotes an existing staff member', () =>
  assertSucceeds(updateDoc(doc(as('ownerA'),'users/staffA'),{role:'manager',roleId:'manager'})));
await check('user edits their own profile name', () =>
  assertSucceeds(updateDoc(doc(as('staffA'),'users/staffA'),{name:'Renamed'})));
await check('user stays on their current workspace', () =>
  assertSucceeds(updateDoc(doc(as('staffA'),'users/staffA'),{companyId:'companyA',name:'X'})));
await check('user switches into a workspace they hold a member doc for', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(),'companies/companyB/members/staffA'),{uid:'staffA',role:'staff'}));
  return assertSucceeds(updateDoc(doc(as('staffA'),'users/staffA'),{companyId:'companyB'}));
});
await check('workspace creator switches in as admin', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db,'users/founder'),{uid:'founder',email:'f@c.com',role:'staff',roleId:'staff',companyId:'companyA',permissions:{},companyMemberships:[{companyId:'companyA'},{companyId:'companyC'}]});
    await setDoc(doc(db,'companies/companyC/members/founder'),{uid:'founder',role:'admin'});
  });
  return assertSucceeds(updateDoc(doc(as('founder'),'users/founder'),{companyId:'companyC',role:'admin',roleId:'owner'}));
});
await check('member doc created with a valid join code', () =>
  assertSucceeds(setDoc(doc(as('joiner'),'companies/companyA/members/joiner'),{uid:'joiner',role:'staff',joinCode:'ABC123'})));
await check('staff writes an audit log attributed to themselves', () =>
  assertSucceeds(setDoc(doc(as('staffA'),'companies/companyA/auditLogs/a2'),{userId:'staffA',action:'stock_in'})));
await check('member marks a company notification read', () =>
  assertSucceeds(updateDoc(doc(as('staffA'),'companies/companyA/notifications/n1'),{isRead:true})));
await check('admin lists their own companys invites', () =>
  assertSucceeds(getDocs(collection(as('ownerA'),'companies/companyA/invites'))));
await check('staff reads their own companys products', () =>
  assertSucceeds(getDoc(doc(as('staffA'),'companies/companyA/products/p1'))));

console.log('\n--- SUPER ADMIN BOUNDARY ---');
await check('a normal user cannot read another companys doc', () =>
  assertFails(getDoc(doc(as('staffA'),'companies/companyB'))));
await check('a normal user cannot list companies', () =>
  assertFails(getDocs(collection(as('staffA'),'companies'))));
await check('a user cannot make themselves a super admin', () =>
  assertFails(setDoc(doc(as('staffA'),'superAdmins/staffA'),{note:'me'})));
await check('a super admin cannot be granted by another super admin either', () =>
  assertFails(setDoc(doc(as('root'),'superAdmins/staffA'),{note:'promote'})));
await check('a user cannot enumerate super admins', () =>
  assertFails(getDocs(collection(as('staffA'),'superAdmins'))));
await check('a user can check whether they are a super admin', () =>
  assertSucceeds(getDoc(doc(as('staffA'),'superAdmins/staffA'))));
await check('super admin lists every company', () =>
  assertSucceeds(getDocs(collection(as('root'),'companies'))));
await check('super admin reads inside any company', () =>
  assertSucceeds(getDoc(doc(as('root'),'companies/companyB/products/p9'))));
await check('super admin writes inside any company', () =>
  assertSucceeds(setDoc(doc(as('root'),'companies/companyB/products/pNew'),{name:'X',quantity:1})));
await check('super admin changes a companys plan', () =>
  assertSucceeds(updateDoc(doc(as('root'),'companies/companyA'),{plan:{planId:'free',status:'active'}})));
await check('super admin suspends a company', () =>
  assertSucceeds(updateDoc(doc(as('root'),'companies/companyA'),{status:'suspended'})));

console.log('\n--- SUSPENSION ---');
await check('a suspended companys member cannot write', () =>
  assertFails(setDoc(doc(as('staffS'),'companies/companyS/products/p2'),{name:'New',quantity:1})));
await check('a suspended companys member cannot update either', () =>
  assertFails(updateDoc(doc(as('staffS'),'companies/companyS/products/p1'),{quantity:99})));
await check('a suspended companys member can still READ their own data', () =>
  assertSucceeds(getDoc(doc(as('staffS'),'companies/companyS/products/p1'))));
await check('super admin can still write to a suspended company (to lift it)', () =>
  assertSucceeds(updateDoc(doc(as('root'),'companies/companyS'),{status:'active'})));
await check('an active companys member is unaffected', () =>
  assertSucceeds(setDoc(doc(as('ownerA'),'companies/companyA/products/pOk'),{name:'Ok',quantity:1})));

console.log('\n--- COMPANY DOC SELF-SERVICE ---');
// A company admin could previously write any field on their own company doc.
// That made suspension decorative against the very person it targets, and
// would have handed out free plan upgrades the moment paid tiers existed.
await check('a suspended company admin cannot lift their own suspension', () =>
  assertFails(updateDoc(doc(as('staffS'),'companies/companyS'),{status:'active'})));
await check('a company admin cannot set their own plan', () =>
  assertFails(updateDoc(doc(as('ownerA'),'companies/companyA'),{plan:{planId:'enterprise',status:'active'}})));
await check('a company admin cannot reassign ownership', () =>
  assertFails(updateDoc(doc(as('ownerA'),'companies/companyA'),{adminUid:'mallory'})));
await check('a company admin cannot edit another companys doc', () =>
  assertFails(updateDoc(doc(as('ownerA'),'companies/companyB'),{companyName:'Pwned'})));
await check('a company admin cannot promote a user in another company', () =>
  assertFails(updateDoc(doc(as('ownerA'),'users/ownerB'),{role:'staff'})));
await check('a company admin cannot write app-wide metadata', () =>
  assertFails(updateDoc(doc(as('ownerA'),'metadata/app'),{firstUserCreated:false})));

console.log('\n--- COMPANY CREATION ---');
await check('cannot create a company owned by someone else', () =>
  assertFails(setDoc(doc(as('mallory'),'companies/cX1'),{companyName:'X',adminUid:'victim'})));
await check('cannot create a company on a paid plan', () =>
  assertFails(setDoc(doc(as('mallory'),'companies/cX2'),{companyName:'X',adminUid:'mallory',plan:{planId:'enterprise'}})));
await check('cannot create a company already suspended', () =>
  assertFails(setDoc(doc(as('mallory'),'companies/cX3'),{companyName:'X',adminUid:'mallory',status:'suspended'})));
await check('cannot create a company already deleted', () =>
  assertFails(setDoc(doc(as('mallory'),'companies/cX4'),{companyName:'X',adminUid:'mallory',status:'deleted'})));
await check('signing up creates a workspace you own', () =>
  assertSucceeds(setDoc(doc(as('newbie'),'companies/cNew'),{companyName:'New',adminUid:'newbie',createdAt:new Date()})));
await check('a company admin can still rename their own company', () =>
  assertSucceeds(updateDoc(doc(as('ownerA'),'companies/companyA'),{companyName:'Renamed'})));
await check('a company admin can still edit their own settings', () =>
  assertSucceeds(updateDoc(doc(as('ownerA'),'companies/companyA'),{settings:{pricingEnabled:false}})));
await check('a half-finished signup can delete its own empty company', async () => {
  // If the user doc write fails, belongsToCompany() is false because the doc
  // is what it reads. Without a creator branch the company is undeletable and
  // the account is stranded: unusable, and the email cannot be reused.
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(),'companies/companyOrphan'),{companyName:'Half',adminUid:'halfUser'}));
  return assertSucceeds(deleteDoc(doc(as('halfUser'),'companies/companyOrphan')));
});
await check('you cannot delete a company you did not create', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(),'companies/companyOther'),{companyName:'Other',adminUid:'someoneElse'}));
  return assertFails(deleteDoc(doc(as('mallory'),'companies/companyOther')));
});
await check('a super admin can still change plan and status', async () => {
  await assertSucceeds(updateDoc(doc(as('root'),'companies/companyA'),{plan:{planId:'free',status:'active'}}));
  return assertSucceeds(updateDoc(doc(as('root'),'companies/companyA'),{status:'suspended'}));
});

await env.cleanup();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail===0?0:1);

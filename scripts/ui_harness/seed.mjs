/**
 * Seeds the Firebase emulators with a demo workspace for the UI harness.
 *
 * Everything goes through the Admin SDK, which bypasses firestore.rules, so the
 * data can be laid down in one pass. The app itself still runs under the real
 * rules: the emulator loads firestore.rules from the repo root.
 *
 * Roles are deliberately NOT seeded. The app seeds the default roles itself the
 * first time the owner signs in (AuthService.ensureRolesSeeded), so they always
 * match lib/models/role_model.dart. Sign in as the owner before anyone else.
 *
 * Usage (emulators running, see README.md):
 *   node seed.mjs            # wipe the demo project, then seed it
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

const { initializeApp } = await import('firebase-admin/app');
const { getAuth } = await import('firebase-admin/auth');
const { getFirestore, Timestamp } = await import('firebase-admin/firestore');

/** Must match DevEmulators.options.projectId in lib/config/dev_emulators.dart. */
export const PROJECT_ID = 'demo-smartshelf';
export const PASSWORD = 'demo-pass-1234';
export const USERS = {
  owner: { email: 'owner@demo.test', name: 'Asha Kulkarni' },
  staff: { email: 'staff@demo.test', name: 'Ravi Menon' },
};
const COMPANY_ID = 'demo-traders';
const COMPANY_NAME = 'Demo Traders';
const JOIN_CODE = 'DEMO42';

initializeApp({ projectId: PROJECT_ID });
const auth = getAuth();
const db = getFirestore();

const DAY = 24 * 3600 * 1000;
const at = (daysAgo) => Timestamp.fromDate(new Date(Date.now() - daysAgo * DAY));

async function wipe() {
  // The emulators expose reset endpoints; nothing here can reach a real project.
  const fsHost = process.env.FIRESTORE_EMULATOR_HOST;
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  await fetch(`http://${fsHost}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://${authHost}/emulator/v1/projects/${PROJECT_ID}/accounts`, { method: 'DELETE' });
}

async function createUser({ email, name }) {
  const user = await auth.createUser({ email, password: PASSWORD, displayName: name });
  return user.uid;
}

const categories = [
  ['beverages', 'Beverages'],
  ['snacks', 'Snacks'],
  ['household', 'Household'],
  ['personal', 'Personal Care'],
];

const vendors = [
  ['v1', 'Sunrise Distributors', 'Meera Shah', '9820011111'],
  ['v2', 'Konkan Foods Wholesale', 'Imran Qureshi', '9820022222'],
  ['v3', 'Metro Household Supplies', 'Lakshmi Iyer', '9820033333'],
];

const customers = [
  ['c1', 'Patel General Store', '9811100001'],
  ['c2', 'Shree Ganesh Wholesale Traders & Distributors Private Limited', '9811100002'],
  ['c3', 'Cafe Aroma', '9811100003'],
  ['c4', 'Green Leaf Supermarket', '9811100004'],
  ['c5', 'Walk-in Customer', '9811100005'],
];

// [id, name, categoryId, brand, qtyMain, qtyWarehouse, threshold, cost, price, barcode]
const products = [
  ['p01', 'Masala Chai 250g', 'beverages', 'Acme', 40, 120, 20, 95, 140, '8901000000011'],
  ['p02', 'Filter Coffee Powder 500g', 'beverages', 'Acme', 6, 10, 20, 210, 299, '8901000000028'],
  ['p03', 'Mango Drink 1L', 'beverages', 'Globex', 0, 0, 12, 48, 70, '8901000000035'],
  ['p04', 'Salted Peanuts 200g', 'snacks', 'Globex', 55, 80, 25, 30, 45, '8901000000042'],
  ['p05', 'Extra Long Product Name For Layout Testing Premium Assorted Dry Fruit Gift Box 1kg', 'snacks', 'Acme', 3, 4, 5, 780, 1150, '8901000000059'],
  ['p06', 'Potato Chips Classic 150g', 'snacks', 'Globex', 90, 200, 40, 18, 30, '8901000000066'],
  ['p07', 'Dishwash Liquid 750ml', 'household', 'Acme', 25, 60, 15, 85, 125, '8901000000073'],
  ['p08', 'Floor Cleaner 1L', 'household', 'Globex', 12, 30, 15, 99, 149, '8901000000080'],
  ['p09', 'Laundry Detergent 2kg', 'household', 'Acme', 18, 40, 10, 240, 345, '8901000000097'],
  ['p10', 'Herbal Shampoo 340ml', 'personal', 'Globex', 33, 50, 12, 150, 225, '8901000000103'],
  ['p11', 'Toothpaste 150g', 'personal', 'Acme', 70, 140, 30, 55, 85, '8901000000110'],
  ['p12', 'Hand Wash Refill 750ml', 'personal', 'Globex', 2, 0, 10, 90, 135, '8901000000127'],
];

const productById = Object.fromEntries(products.map((p) => [p[0], p]));

function line(productId, quantity) {
  const p = productById[productId];
  return {
    productId,
    productName: p[1],
    quantity,
    unit: 'pcs',
    unitPrice: p[8],
    discountPercent: 0,
    taxRate: 18,
    location: 'Main Store',
  };
}

function invoice({ number, customer, items, daysAgo, paid, status, type = 'sales', vendor }) {
  const subtotal = items.reduce((s, i) => s + i.quantity * i.unitPrice, 0);
  const totalTax = Math.round(subtotal * 0.18 * 100) / 100;
  const grandTotal = Math.round((subtotal + totalTax) * 100) / 100;
  const amountPaid = paid === 'all' ? grandTotal : paid;
  return {
    invoiceType: type,
    invoiceNumber: number,
    customerId: customer ? customer[0] : '',
    customerName: customer ? customer[1] : '',
    customerPhone: customer ? customer[2] : '',
    customerAddress: '',
    vendorId: vendor ? vendor[0] : '',
    vendorName: vendor ? vendor[1] : '',
    status,
    items,
    discountPercent: 0,
    discountAmount: 0,
    taxLabel: 'GST',
    subtotal,
    totalDiscount: 0,
    invoiceDiscount: 0,
    totalTax,
    grandTotal,
    amountPaid,
    amountDue: Math.round((grandTotal - amountPaid) * 100) / 100,
    payments: amountPaid > 0
      ? [{ id: `${number}-pay`, amount: amountPaid, date: at(daysAgo), method: 'upi', referenceNumber: '', notes: '' }]
      : [],
    invoiceDate: at(daysAgo),
    dueDate: at(daysAgo - 15),
    notes: '',
    termsText: '',
    linkedSalesOrderId: '',
    linkedPurchaseOrderId: '',
    linkedCreditNoteId: '',
    registerSessionId: '',
    creditedAmount: 0,
    stockDeducted: true,
    createdBy: '',
    createdByName: '',
    createdAt: at(daysAgo),
    updatedAt: at(daysAgo),
  };
}

async function seed() {
  await wipe();
  const ownerUid = await createUser(USERS.owner);
  const staffUid = await createUser(USERS.staff);

  const company = db.doc(`companies/${COMPANY_ID}`);
  await company.set({
    companyName: COMPANY_NAME,
    adminUid: ownerUid,
    phone: '9800012345',
    createdAt: at(60),
    permanentJoinCode: JOIN_CODE,
    plan: { planId: 'max', status: 'active', startedAt: at(60), note: '' },
    settings: {
      pricingEnabled: true,
      vendorsEnabled: true,
      barcodeEnabled: true,
      companies: ['Acme', 'Globex'],
      sizes: [],
      locations: ['Main Store', 'Warehouse'],
      // What a new signup starts with: FeatureMap.hiddenForNewWorkspaces.
      hiddenFeatures: [
        'abcAnalysis', 'boms', 'budgets', 'commissions', 'creditControl',
        'expenses', 'jobWork', 'priceLists', 'quotations', 'recurringInvoices',
        'registerSessions', 'requisitions', 'serials', 'serviceJobs',
        'shipments', 'stockForecast', 'transferOrders', 'valuationTrends',
        'vendorScorecard',
      ],
      billing: {
        billingEnabled: true,
        businessName: COMPANY_NAME,
        businessPhone: '9800012345',
        businessEmail: 'accounts@demo.test',
        businessAddress: '12 Market Road, Pune',
        currencySymbol: '₹',
        enableTax: true,
        taxLabel: 'GST',
        defaultTaxRate: 18,
        taxInclusive: false,
        enableDiscounts: true,
        enablePaymentTracking: true,
        defaultPaymentTermDays: 15,
        invoicePrefix: 'INV-',
        nextInvoiceNumber: 7,
        purchasePrefix: 'PUR-',
        nextPurchaseNumber: 2,
      },
    },
  });
  await db.doc(`joinCodeIndex/${JOIN_CODE}`).set({ companyId: COMPANY_ID, companyName: COMPANY_NAME });

  const membership = (role, roleId) => ({ companyId: COMPANY_ID, companyName: COMPANY_NAME, role, roleId });
  const people = [
    [ownerUid, USERS.owner, 'admin', 'owner'],
    [staffUid, USERS.staff, 'staff', 'staff'],
  ];
  for (const [uid, who, role, roleId] of people) {
    await db.doc(`users/${uid}`).set({
      uid,
      name: who.name,
      email: who.email,
      role,
      roleId,
      companyId: COMPANY_ID,
      companyName: COMPANY_NAME,
      phone: '',
      createdAt: at(60),
      permissions: {},
      companyMemberships: [membership(role, roleId)],
    });
    await company.collection('members').doc(uid).set({
      uid, role, roleId, email: who.email, name: who.name, joinedAt: at(60),
    });
  }

  const stamp = { createdAt: at(50), updatedAt: at(2), createdBy: ownerUid, createdByName: USERS.owner.name };
  for (const [id, name] of categories) {
    await company.collection('categories').doc(id).set({ name, description: '', ...stamp, updatedBy: ownerUid, updatedByName: USERS.owner.name });
  }
  for (const [id, name, contactName, phone] of vendors) {
    await company.collection('vendors').doc(id).set({
      name, contactName, email: '', phone, address: '', leadTimeDays: 5, rating: 4, notes: '', isActive: true, ...stamp,
    });
  }
  for (const [id, name, phone] of customers) {
    await company.collection('customers').doc(id).set({
      name, email: '', phone, address: '', company: '', notes: '', totalOrders: 0, totalSpent: 0,
      creditLimit: 0, paymentTermDays: 15, creditHold: false, isActive: true, ...stamp,
    });
  }
  const categoryName = Object.fromEntries(categories);
  for (const [id, name, categoryId, brand, main, warehouse, threshold, cost, price, barcode] of products) {
    await company.collection('products').doc(id).set({
      name, categoryId, categoryName: categoryName[categoryId], company: brand, size: '',
      quantity: main + warehouse, heldQuantity: 0, unit: 'pcs', baseUnit: 'pcs', packUnit: '', unitsPerPack: 1,
      locationQuantities: { 'Main Store': main, Warehouse: warehouse }, heldLocationQuantities: {},
      description: '', lowStockThreshold: threshold, costPrice: cost, sellingPrice: price,
      ...stamp, updatedBy: ownerUid, updatedByName: USERS.owner.name,
      preferredVendorId: '', preferredVendorName: '', lastVendorId: '', lastVendorName: '', vendorPrices: {}, barcode,
    });
  }

  const invoices = [
    invoice({ number: 'INV-0001', customer: customers[0], items: [line('p01', 10), line('p04', 20)], daysAgo: 21, paid: 'all', status: 'paid' }),
    invoice({ number: 'INV-0002', customer: customers[1], items: [line('p05', 2), line('p09', 6), line('p11', 24)], daysAgo: 14, paid: 2000, status: 'partiallyPaid' }),
    invoice({ number: 'INV-0003', customer: customers[2], items: [line('p02', 4)], daysAgo: 9, paid: 0, status: 'sent' }),
    invoice({ number: 'INV-0004', customer: customers[3], items: [line('p06', 48), line('p10', 6)], daysAgo: 40, paid: 0, status: 'overdue' }),
    invoice({ number: 'INV-0005', customer: customers[4], items: [line('p07', 2)], daysAgo: 1, paid: 'all', status: 'paid' }),
    invoice({ number: 'INV-0006', customer: customers[0], items: [line('p08', 3), line('p12', 2)], daysAgo: 0, paid: 'all', status: 'paid' }),
    invoice({ number: 'PUR-0001', vendor: vendors[0], items: [line('p01', 60), line('p02', 20)], daysAgo: 30, paid: 'all', status: 'paid', type: 'purchase' }),
  ];
  for (const [i, inv] of invoices.entries()) {
    await company.collection('invoices').doc(`inv${i + 1}`).set({ ...inv, createdBy: ownerUid, createdByName: USERS.owner.name });
  }

  // A month of stock movements, so the ledger and reports have something to show.
  let n = 0;
  for (const [id, name] of products) {
    for (const [type, qty, daysAgo] of [['stock_in', 50, 28], ['stock_out', 12, 12], ['stock_out', 5, 3]]) {
      n += 1;
      await company.collection('transactions').doc(`t${n}`).set({
        productId: id, productName: name, type, quantity: qty,
        quantityDelta: type === 'stock_in' ? qty : -qty,
        location: 'Main Store', reason: '', userId: ownerUid, userName: USERS.owner.name,
        date: at(daysAgo), vendorId: '', vendorName: '',
      });
    }
  }

  console.log(`Seeded ${COMPANY_NAME}: owner ${USERS.owner.email}, staff ${USERS.staff.email}, password ${PASSWORD}`);
}

// Run when executed directly; shoot.mjs imports the constants above.
if (import.meta.url === `file://${process.argv[1]}`) {
  await seed();
  process.exit(0);
}

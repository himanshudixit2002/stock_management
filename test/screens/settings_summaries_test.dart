import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/screens/settings/settings_summaries.dart';

void main() {
  group('formatting helpers', () {
    test('a whole tax rate loses its decimals', () {
      expect(formatRate(18), '18');
      expect(formatRate(0), '0');
    });

    test('a fractional rate keeps two places', () {
      expect(formatRate(18.5), '18.50');
      expect(formatRate(2.25), '2.25');
    });

    test('document numbers pad to four digits, as they print', () {
      expect(formatDocumentNumber('INV', 42), 'INV-0042');
      expect(formatDocumentNumber('INV', 1), 'INV-0001');
      expect(formatDocumentNumber('BILL', 12345), 'BILL-12345');
    });
  });

  group('appearanceSummary', () {
    test('names the theme and counts the quick actions', () {
      expect(
        appearanceSummary(
          mode: ThemeMode.dark,
          quickActionCount: 6,
          loaded: true,
        ),
        'Dark · 6 quick actions',
      );
      expect(
        appearanceSummary(
          mode: ThemeMode.system,
          quickActionCount: 1,
          loaded: true,
        ),
        'System theme · 1 quick action',
      );
    });

    test('falls back to a description before prefs load', () {
      expect(
        appearanceSummary(
          mode: ThemeMode.light,
          quickActionCount: 0,
          loaded: false,
        ),
        'Theme and home quick actions',
      );
    });
  });

  group('notificationsSummary', () {
    test('counts the enabled types', () {
      expect(
        notificationsSummary(
          enabled: 4,
          total: 6,
          expiryDays: 30,
          trayAvailable: true,
        ),
        '4 of 6 alerts · this device',
      );
    });

    test('says so plainly when every alert is off', () {
      expect(
        notificationsSummary(
          enabled: 0,
          total: 6,
          expiryDays: 30,
          trayAvailable: true,
        ),
        'All alerts off · this device',
      );
    });

    test('collapses the all-on case', () {
      expect(
        notificationsSummary(
          enabled: 6,
          total: 6,
          expiryDays: 30,
          trayAvailable: true,
        ),
        'All 6 alerts on · this device',
      );
    });

    test('does not promise a tray where there is none', () {
      expect(
        notificationsSummary(
          enabled: 3,
          total: 6,
          expiryDays: 30,
          trayAvailable: false,
        ),
        '3 of 6 alerts · in-app only',
      );
    });
  });

  group('featuresSummary', () {
    test('splits the switches into on and off', () {
      expect(
        featuresSummary(
          pricing: true,
          vendors: false,
          barcode: true,
          billing: false,
          loaded: true,
        ),
        'Pricing, Barcode on · Vendors, Billing off',
      );
    });

    test('collapses the all-on and all-off cases', () {
      expect(
        featuresSummary(
          pricing: true,
          vendors: true,
          barcode: true,
          billing: true,
          loaded: true,
        ),
        'All four features on',
      );
      expect(
        featuresSummary(
          pricing: false,
          vendors: false,
          barcode: false,
          billing: false,
          loaded: true,
        ),
        'All four features off',
      );
    });

    test('falls back before the company doc loads', () {
      expect(
        featuresSummary(
          pricing: true,
          vendors: true,
          barcode: true,
          billing: true,
          loaded: false,
        ),
        'Pricing, vendors, barcode and billing',
      );
    });
  });

  group('billingSummary', () {
    test('reads currency, tax and the next number', () {
      expect(
        billingSummary(
          loaded: true,
          currencySymbol: '₹',
          taxLabel: 'GST',
          taxRate: 18,
          enableTax: true,
          invoicePrefix: 'INV',
          nextInvoiceNumber: 42,
        ),
        '₹ · GST 18% · INV-0042 next',
      );
    });

    test('says "no tax" rather than showing a rate that is not applied', () {
      expect(
        billingSummary(
          loaded: true,
          currencySymbol: r'$',
          taxLabel: 'GST',
          taxRate: 18,
          enableTax: false,
          invoicePrefix: 'INV',
          nextInvoiceNumber: 1,
        ),
        r'$ · no tax · INV-0001 next',
      );
    });

    test('keeps a fractional rate', () {
      expect(
        billingSummary(
          loaded: true,
          currencySymbol: '₹',
          taxLabel: 'VAT',
          taxRate: 18.5,
          enableTax: true,
          invoicePrefix: 'INV',
          nextInvoiceNumber: 7,
        ),
        '₹ · VAT 18.50% · INV-0007 next',
      );
    });

    test('does not flash defaults before the settings load', () {
      // Without this the row would read "\$ · Tax 0% · INV-0001 next" for a
      // frame and then correct itself, which looks like broken data.
      expect(
        billingSummary(
          loaded: false,
          currencySymbol: r'$',
          taxLabel: 'GST',
          taxRate: 0,
          enableTax: true,
          invoicePrefix: 'INV',
          nextInvoiceNumber: 1,
        ),
        'Company profile, tax and numbering',
      );
    });
  });

  group('catalogSummary', () {
    test('counts each list and pluralises', () {
      expect(
        catalogSummary(
          categories: 12,
          companies: 8,
          subCategories: 3,
          locations: 1,
          loaded: true,
        ),
        '12 categories · 8 companies · 3 sub-categories · 1 location',
      );
    });

    test('drops the lists that are empty', () {
      expect(
        catalogSummary(
          categories: 12,
          companies: 0,
          subCategories: 0,
          locations: 4,
          loaded: true,
        ),
        '12 categories · 4 locations',
      );
    });

    test('says nothing is set up when every list is empty', () {
      expect(
        catalogSummary(
          categories: 0,
          companies: 0,
          subCategories: 0,
          locations: 0,
          loaded: true,
        ),
        'Nothing set up yet',
      );
    });
  });

  group('teamSummary', () {
    test('counts roles and names what else is behind the row', () {
      expect(
        teamSummary(
          roleCount: 4,
          rolesLoaded: true,
          canManageUsers: true,
          vendorsOn: true,
        ),
        '4 roles · users & overrides · vendors',
      );
      expect(
        teamSummary(
          roleCount: 1,
          rolesLoaded: true,
          canManageUsers: false,
          vendorsOn: false,
        ),
        '1 role',
      );
    });

    test('falls back before roles stream in', () {
      expect(
        teamSummary(
          roleCount: 0,
          rolesLoaded: false,
          canManageUsers: true,
          vendorsOn: true,
        ),
        'Users, roles, vendors and customers',
      );
    });
  });

  group('dataSummary', () {
    test('lists only what the user may actually do', () {
      expect(
        dataSummary(canImport: true, canExport: true, canDataHealth: true),
        'Import, Export, Data health',
      );
      expect(
        dataSummary(canImport: true, canExport: false, canDataHealth: false),
        'Import',
      );
      expect(
        dataSummary(canImport: false, canExport: false, canDataHealth: false),
        'Bulk actions and workspace tools',
      );
    });
  });

  group('planSummary', () {
    test('names the tier and its state', () {
      expect(
        planSummary(
          planLabel: 'Growth',
          usable: true,
          statusNote: '',
          loaded: true,
        ),
        'Growth plan · active',
      );
    });

    test('surfaces why an unusable workspace is blocked', () {
      expect(
        planSummary(
          planLabel: 'Growth',
          usable: false,
          statusNote: 'payment past due',
          loaded: true,
        ),
        'Growth plan · payment past due',
      );
      expect(
        planSummary(
          planLabel: 'Growth',
          usable: false,
          statusNote: '',
          loaded: true,
        ),
        'Growth plan',
      );
    });

    test('falls back before the company doc loads', () {
      expect(
        planSummary(
          planLabel: 'MAX Tier',
          usable: true,
          statusNote: '',
          loaded: false,
        ),
        'What your tier includes',
      );
    });
  });

  group('helpSummary', () {
    test('shows the version once package info answers', () {
      expect(helpSummary(appVersion: '1.0.28'), 'Guides, legal and v1.0.28');
      expect(helpSummary(appVersion: ''), 'Guides, policies and app info');
    });
  });

  group('accountSummary', () {
    test('pairs the email with the role', () {
      expect(
        accountSummary(email: 'a@b.com', roleLabel: 'Admin'),
        'a@b.com · Admin',
      );
      expect(accountSummary(email: 'a@b.com', roleLabel: ''), 'a@b.com');
    });
  });
}

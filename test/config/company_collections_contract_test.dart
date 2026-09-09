import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/super_admin_service.dart';

void main() {
  /// The catalog in [SuperAdminService] is what a purge iterates, what the
  /// console counts, and what its browser renders. Nothing in the type system
  /// links it to the collections the app actually writes, so this test reads the
  /// source and does it by hand.
  ///
  /// It exists because that link was missing once already: the purge list was
  /// written before the feature modules and never grew with them, so seven
  /// collections' worth of a deleted workspace stayed in Firestore — a purge
  /// that reported success and left tenant data behind.
  group('company collection catalog', () {
    /// Root collections, which are not part of a company and must not be in the
    /// catalog.
    const rootCollections = {
      'companies',
      'users',
      'plans',
      'publicConfig',
      'joinCodeIndex',
      'platformAuditLogs',
      'superAdmins',
      'metadata',
    };

    /// Every `.collection('x')` the app source mentions.
    Set<String> collectionsInSource() {
      final pattern = RegExp(r"\.collection\('([A-Za-z]+)'\)");
      final found = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final match in pattern.allMatches(entity.readAsStringSync())) {
          found.add(match.group(1)!);
        }
      }
      return found;
    }

    test('every collection the app writes under a company is catalogued', () {
      final catalogued = SuperAdminService.companySubcollections.toSet();
      final missing = collectionsInSource()
          .difference(rootCollections)
          .difference(catalogued)
          .toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'These collections exist in the code but are not in '
            'SuperAdminService.companyCollections, so a purge would leave them '
            'behind and the console cannot see them: ${missing.join(', ')}',
      );
    });

    test('the catalog names nothing the app never writes', () {
      // The other direction: a stale entry would have a purge walk a collection
      // that does not exist, and show an empty row in the console for ever.
      final inSource = collectionsInSource();
      final stale = SuperAdminService.companySubcollections
          .where((name) => !inSource.contains(name))
          .toList();
      expect(stale, isEmpty, reason: 'stale catalog entries: $stale');
    });

    test('collection names are unique', () {
      final names = SuperAdminService.companySubcollections;
      expect(names.toSet().length, names.length);
    });

    test('every entry carries a label, and modules are a subset', () {
      for (final collection in SuperAdminService.companyCollections) {
        expect(collection.label.trim(), isNotEmpty, reason: collection.name);
      }
      expect(
        SuperAdminService.moduleCollections.length,
        lessThan(SuperAdminService.companyCollections.length),
      );
      expect(
        SuperAdminService.moduleCollections.every((c) => c.isModule),
        isTrue,
      );
    });

    test('the fifteen module collections are all present', () {
      // Named explicitly: the generic test above passes if a module collection
      // is missing from *both* the catalog and the code, and a module that was
      // dropped from the app entirely is a different conversation.
      const modules = [
        'boms', 'serials', 'transferOrders', 'requisitions',
        'recurringInvoices', 'priceLists', 'landedCosts',
        'quotations', 'shipments', 'expenses', 'registerSessions',
        'commissionPlans', 'budgets', 'serviceJobs', 'jobWorkOrders',
      ];
      final catalogued = SuperAdminService.moduleCollections
          .map((c) => c.name)
          .toSet();
      for (final module in modules) {
        expect(catalogued, contains(module), reason: module);
      }
      expect(catalogued.length, modules.length);
    });

    test('a browsable collection orders on a field or says it cannot', () {
      // An orderBy naming a field the documents do not carry would silently
      // return nothing — Firestore excludes documents missing the ordered
      // field, which is exactly what keeps the register lock out of the shift
      // list. Empty is the honest way to say "no timestamp to order on".
      for (final collection in SuperAdminService.companyCollections) {
        expect(
          collection.orderBy,
          anyOf(
            isEmpty,
            matches(RegExp(r'^[a-zA-Z]+$')),
          ),
          reason: collection.name,
        );
      }
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/models/company_plan_model.dart';
import 'package:stock_management/providers/plan_catalog_provider.dart';
import 'package:stock_management/services/plan_catalog_service.dart';

/// A catalog whose published tiers can be pushed at will.
class _ControllableService extends PlanCatalogService {
  final _controller = StreamController<List<PlanDefinition>>.broadcast();
  final List<PlanDefinition> saved = [];
  final List<String> deleted = [];
  bool failWrites = false;

  @override
  Stream<List<PlanDefinition>> watchPlans() => _controller.stream;

  @override
  Future<void> savePlan(PlanDefinition plan) async {
    if (failWrites) throw Exception('denied');
    saved.add(plan);
  }

  @override
  Future<void> deletePlan(String planId) async {
    if (failWrites) throw Exception('denied');
    deleted.add(planId);
  }

  void publish(List<PlanDefinition> plans) => _controller.add(plans);
  void fail() => _controller.addError(Exception('denied'));
  Future<void> close() => _controller.close();
}

void main() {
  tearDown(PlanCatalog.resetToSeed);

  group('PlanCatalogProvider', () {
    test('a published catalog reaches PlanCatalog and notifies', () async {
      // The notification is the whole point. The first version hydrated the
      // global catalog and signalled with a setState on the app shell — which
      // does nothing, because the shell returns a const widget and Flutter
      // skips an identical subtree. Nothing repainted.
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service);

      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.start();

      service.publish(const [
        PlanDefinition(id: 'lite', label: 'Lite', description: ''),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, greaterThan(0));
      expect(provider.plans.map((p) => p.id), ['lite']);
      expect(PlanCatalog.byId('lite').label, 'Lite');
      expect(provider.loaded, isTrue);
    });

    test('a second publish replaces the first', () async {
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service);
      provider.start();

      service.publish(const [
        PlanDefinition(id: 'lite', label: 'Lite', description: ''),
      ]);
      await Future<void>.delayed(Duration.zero);
      service.publish(const [
        PlanDefinition(id: 'lite', label: 'Lite Renamed', description: ''),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(provider.plans.single.label, 'Lite Renamed');
    });

    test('a failed read leaves the compiled tiers and reports why', () async {
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service);
      provider.start();

      service.fail();
      await Future<void>.delayed(Duration.zero);

      expect(provider.error, isNotNull);
      expect(provider.plans, PlanCatalog.seedDefaults);
    });

    test('start is idempotent', () async {
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service)
        ..start()
        ..start();

      var notifications = 0;
      provider.addListener(() => notifications++);
      service.publish(const [
        PlanDefinition(id: 'one', label: 'One', description: ''),
      ]);
      await Future<void>.delayed(Duration.zero);

      // One subscription, so one notification — not two.
      expect(notifications, 1);
    });

    test('savePlan reports success and failure', () async {
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service);

      const plan = PlanDefinition(id: 'x', label: 'X', description: '');
      expect(await provider.savePlan(plan), isTrue);
      expect(service.saved.single.id, 'x');

      service.failWrites = true;
      expect(await provider.savePlan(plan), isFalse);
      expect(provider.busy, isFalse);
    });

    test('deletePlan reports success and failure', () async {
      final service = _ControllableService();
      addTearDown(service.close);
      final provider = PlanCatalogProvider(service: service);

      expect(await provider.deletePlan('x'), isTrue);
      expect(service.deleted, ['x']);

      service.failWrites = true;
      expect(await provider.deletePlan('y'), isFalse);
    });
  });

  testWidgets('a published edit repaints a widget watching the catalog', (
    tester,
  ) async {
    // The end-to-end version of the bug: editing a tier in the console left the
    // old price on screen.
    final service = _ControllableService();
    addTearDown(service.close);
    final provider = PlanCatalogProvider(service: service)..start();

    await tester.pumpWidget(
      ChangeNotifierProvider<PlanCatalogProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final catalog = context.watch<PlanCatalogProvider>();
              return Scaffold(
                body: Column(
                  children: [
                    for (final plan in catalog.plans) Text(plan.label),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Starter'), findsOneWidget);

    service.publish(const [
      PlanDefinition(id: 'starter', label: 'Starter Plus', description: ''),
    ]);
    await tester.pump();

    expect(find.text('Starter Plus'), findsOneWidget);
    expect(find.text('Starter'), findsNothing);
  });
}

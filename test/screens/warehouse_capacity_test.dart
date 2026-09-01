import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/models/warehouse_zone_model.dart';
import 'package:stock_management/screens/warehouse/warehouse_zones_screen.dart';

WarehouseZoneModel zone({
  int capacity = 100,
  int currentStock = 0,
  String location = 'Main',
  bool isActive = true,
}) {
  final now = DateTime(2026, 1, 1);
  return WarehouseZoneModel(
    id: 'z',
    locationName: location,
    zoneName: 'Zone',
    capacity: capacity,
    currentStock: currentStock,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('warehouseCapacityOf', () {
    test('sums capacity and usage across zones', () {
      final use = warehouseCapacityOf([
        zone(capacity: 100, currentStock: 40),
        zone(capacity: 50, currentStock: 10),
      ]);
      expect(use.capacity, 150);
      expect(use.used, 50);
      expect(use.free, 100);
      expect(use.percent, 33);
    });

    test('counts zones holding more than they are rated for', () {
      final use = warehouseCapacityOf([
        zone(capacity: 10, currentStock: 25),
        zone(capacity: 10, currentStock: 5),
        zone(capacity: 10, currentStock: 10),
      ]);
      expect(use.overCapacity, 1);
    });

    test('an unrated zone does not count as over capacity', () {
      // capacity 0 means "not rated", not "full" — treating it as over would
      // flag every zone that has simply never had a capacity set.
      final use = warehouseCapacityOf([zone(capacity: 0, currentStock: 99)]);
      expect(use.overCapacity, 0);
      expect(use.capacity, 0);
    });

    test('handles no zones at all without dividing by zero', () {
      final use = warehouseCapacityOf([]);
      expect(use.capacity, 0);
      expect(use.ratio, 0);
      expect(use.percent, 0);
      expect(use.free, 0);
    });

    test('ratio never exceeds 1 even when overfilled', () {
      // The progress bar would otherwise be handed a value above 1.
      final use = warehouseCapacityOf([zone(capacity: 10, currentStock: 40)]);
      expect(use.ratio, 1.0);
      expect(use.percent, 100);
      expect(use.free, 0, reason: 'free space cannot go negative');
    });

    test('colour thresholds match the ones the zone cards use', () {
      // A location badge and the cards inside it must never disagree about
      // what "nearly full" means.
      expect(
        warehouseCapacityOf([zone(capacity: 100, currentStock: 50)]).color,
        AppTheme.successColor,
      );
      expect(
        warehouseCapacityOf([zone(capacity: 100, currentStock: 80)]).color,
        AppTheme.warningColor,
      );
      expect(
        warehouseCapacityOf([zone(capacity: 100, currentStock: 95)]).color,
        AppTheme.dangerColor,
      );
    });

    test('exactly at a threshold stays on the calmer colour', () {
      expect(
        warehouseCapacityOf([zone(capacity: 100, currentStock: 70)]).color,
        AppTheme.successColor,
      );
      expect(
        warehouseCapacityOf([zone(capacity: 100, currentStock: 90)]).color,
        AppTheme.warningColor,
      );
    });
  });
}

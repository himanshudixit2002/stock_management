import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/job_work_model.dart';

void main() {
  final now = DateTime(2026, 3, 10);

  JobWorkOrderModel order({
    JobWorkStatus status = JobWorkStatus.draft,
    int outputQuantity = 100,
    int receivedQuantity = 0,
    List<JobWorkComponent> components = const [
      JobWorkComponent(productId: 'p1', quantityPerOutput: 2),
      JobWorkComponent(productId: 'p2', quantityPerOutput: 1),
    ],
    double chargePerUnit = 5,
    double additional = 500,
    DateTime? expectedAt,
    DateTime? issuedAt,
  }) => JobWorkOrderModel(
    id: 'jw1',
    referenceNumber: 'JW-1',
    vendorId: 'v1',
    vendorName: 'Plating Co',
    outputProductId: 'out',
    outputProductName: 'Plated widget',
    outputQuantity: outputQuantity,
    receivedQuantity: receivedQuantity,
    components: components,
    jobChargePerUnit: chargePerUnit,
    additionalCharges: additional,
    issueLocation: 'Main',
    receiveLocation: 'Main',
    status: status,
    expectedAt: expectedAt,
    issuedAt: issuedAt,
    createdAt: now,
    updatedAt: now,
  );

  group('quantities', () {
    test('issuing takes components per finished unit, times the run', () {
      expect(order().issueQuantities, {'p1': 200, 'p2': 100});
    });

    test('a partial receipt consumes its proportional share', () {
      expect(order().consumptionFor(10), {'p1': 20, 'p2': 10});
      expect(order().consumptionFor(0), isEmpty);
    });

    test('what is at the vendor is what was issued less what was used', () {
      final o = order(
        components: const [
          JobWorkComponent(
            productId: 'p1',
            quantityPerOutput: 2,
            issuedQuantity: 200,
            consumedQuantity: 60,
          ),
        ],
      );
      expect(o.components.single.atVendorQuantity, 140);
      expect(o.componentUnitsAtVendor, 140);
      expect(o.componentUnitsIssued, 200);
    });

    test('two lines of the same component are netted, not overwritten', () {
      // A map keyed on product id would keep only the last line and issue half
      // of what the job actually needs.
      final o = order(
        outputQuantity: 10,
        components: const [
          JobWorkComponent(productId: 'p1', quantityPerOutput: 2),
          JobWorkComponent(productId: 'p1', quantityPerOutput: 3),
        ],
      );
      expect(o.issueQuantities, {'p1': 50});
      expect(o.consumptionFor(4), {'p1': 20});
      // The lines themselves still record their own share.
      expect(o.lineQuantityFor(o.components.first, 10), 20);
      expect(o.lineQuantityFor(o.components.last, 10), 30);
    });

    test('remaining output never goes negative', () {
      expect(order(outputQuantity: 10, receivedQuantity: 12).remainingOutput, 0);
    });
  });

  group('charges', () {
    test('per-unit conversion cost spreads the one-off charges', () {
      final o = order(outputQuantity: 100, chargePerUnit: 5, additional: 500);
      expect(o.chargePerOutputUnit, 10);
      expect(o.chargesPlanned, 1000);
    });

    test('charges incurred follow what has actually come back', () {
      final o = order(receivedQuantity: 40);
      expect(o.chargesIncurred, 40 * 5 + 500);
      expect(order().chargesIncurred, 0);
    });

    test('a job with no planned output falls back to the per-unit charge', () {
      expect(order(outputQuantity: 0).chargePerOutputUnit, 5);
    });
  });

  group('transitions', () {
    test('a draft with components and an output can be issued', () {
      expect(order().canIssue, isTrue);
      expect(order(components: const []).canIssue, isFalse);
      expect(order(outputQuantity: 0).canIssue, isFalse);
      expect(order(status: JobWorkStatus.issued).canIssue, isFalse);
    });

    test('only a job that is out can receive, and only what is left', () {
      expect(order(status: JobWorkStatus.issued).canReceive, isTrue);
      expect(
        order(
          status: JobWorkStatus.issued,
          receivedQuantity: 100,
        ).canReceive,
        isFalse,
      );
      expect(order().canReceive, isFalse);
    });

    test('closing settles a job that is out; a draft is cancelled instead', () {
      expect(order(status: JobWorkStatus.partiallyReceived).canClose, isTrue);
      expect(order().canClose, isFalse);
      expect(order().canCancel, isTrue);
      expect(order(status: JobWorkStatus.issued).canCancel, isFalse);
    });

    test('an issued job past its date is overdue', () {
      final o = order(
        status: JobWorkStatus.issued,
        expectedAt: DateTime(2026, 3, 1),
        issuedAt: DateTime(2026, 2, 20),
      );
      expect(o.isOverdue, isTrue);
      expect(o.daysOut, isNotNull);
      expect(order(expectedAt: DateTime(2020, 1, 1)).isOverdue, isFalse);
    });
  });

  group('serialisation', () {
    test('round-trips through a map', () {
      final original = order(
        status: JobWorkStatus.partiallyReceived,
        receivedQuantity: 30,
        expectedAt: DateTime(2026, 4, 1),
        components: const [
          JobWorkComponent(
            productId: 'p1',
            productName: 'Blank',
            unit: 'pcs',
            quantityPerOutput: 2,
            issuedQuantity: 200,
            consumedQuantity: 60,
          ),
        ],
      );
      final restored = JobWorkOrderModel.fromMap(original.toMap(), 'jw1');
      expect(restored.status, JobWorkStatus.partiallyReceived);
      expect(restored.receivedQuantity, 30);
      expect(restored.expectedAt, DateTime(2026, 4, 1));
      expect(restored.components.single.atVendorQuantity, 140);
      expect(restored.statusLabel, 'Part received');
    });

    test('an empty document reads back as a usable draft', () {
      final restored = JobWorkOrderModel.fromMap(const {}, 'jw9');
      expect(restored.status, JobWorkStatus.draft);
      expect(restored.components, isEmpty);
      expect(restored.canIssue, isFalse);
    });
  });
}

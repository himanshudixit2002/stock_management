import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/service_job_model.dart';

void main() {
  final received = DateTime(2026, 3, 1);

  ServiceJobModel job({
    ServiceJobStatus status = ServiceJobStatus.received,
    List<ServicePart> parts = const [],
    List<ServiceCharge> charges = const [],
    DateTime? warrantyUntil,
    DateTime? promisedAt,
  }) => ServiceJobModel(
    id: 'j1',
    jobNumber: 'JOB-1',
    customerName: 'Acme',
    productName: 'Widget',
    serialNumber: 'SN-1',
    status: status,
    parts: parts,
    charges: charges,
    warrantyUntil: warrantyUntil,
    promisedAt: promisedAt,
    receivedAt: received,
    createdAt: received,
    updatedAt: received,
  );

  group('warranty', () {
    test('is judged as at the day the unit came in, not today', () {
      // A warranty that lapsed while the unit sat on the bench must not turn a
      // free repair into a billable one.
      final j = job(warrantyUntil: DateTime(2026, 3, 5));
      expect(j.warrantyState, WarrantyState.inWarranty);
      expect(j.isUnderWarranty, isTrue);
    });

    test('a unit received after its warranty ended is out of warranty', () {
      final j = job(warrantyUntil: DateTime(2026, 2, 1));
      expect(j.warrantyState, WarrantyState.outOfWarranty);
    });

    test('no warranty date is unknown, not expired', () {
      expect(job().warrantyState, WarrantyState.unknown);
      expect(job().isUnderWarranty, isFalse);
    });
  });

  group('billing', () {
    test('a warranty part leaves stock but is not charged', () {
      final j = job(
        parts: const [
          ServicePart(
            productId: 'p1',
            quantity: 2,
            unitPrice: 500,
            chargeable: false,
          ),
          ServicePart(productId: 'p2', quantity: 1, unitPrice: 300),
        ],
        charges: const [ServiceCharge(label: 'Labour', amount: 400)],
      );
      expect(j.partUnits, 3);
      expect(j.partsTotal, 300);
      expect(j.chargesTotal, 400);
      expect(j.billableTotal, 700);
    });
  });

  group('parts and transitions', () {
    test('a job cannot be resolved with parts still unissued', () {
      // Otherwise the spares are on the customer's machine and still on the
      // shelf as far as the app is concerned.
      final j = job(
        status: ServiceJobStatus.inProgress,
        parts: const [ServicePart(productId: 'p1', quantity: 1)],
      );
      expect(j.hasUnissuedParts, isTrue);
      expect(j.canResolve, isFalse);
      expect(j.canIssueParts, isTrue);
    });

    test('once parts are issued the job can be resolved', () {
      final j = job(
        status: ServiceJobStatus.inProgress,
        parts: const [
          ServicePart(productId: 'p1', quantity: 1, issued: true),
        ],
      );
      expect(j.canResolve, isTrue);
      expect(j.canIssueParts, isFalse);
    });

    test('a job with issued parts cannot be cancelled', () {
      final j = job(
        parts: const [
          ServicePart(productId: 'p1', quantity: 1, issued: true),
        ],
      );
      expect(j.canCancel, isFalse);
      expect(job().canCancel, isTrue);
    });

    test('only a resolved job closes', () {
      expect(job(status: ServiceJobStatus.resolved).canClose, isTrue);
      expect(job(status: ServiceJobStatus.inProgress).canClose, isFalse);
    });

    test('a closed job is no longer open or editable', () {
      final j = job(status: ServiceJobStatus.closed);
      expect(j.isOpen, isFalse);
      expect(j.canEdit, isFalse);
      expect(j.isOverdue, isFalse);
    });
  });

  group('SLA', () {
    test('an open job past its promise is overdue', () {
      final j = job(
        status: ServiceJobStatus.inProgress,
        promisedAt: DateTime(2026, 3, 2),
      );
      expect(j.isOverdue, isTrue);
    });

    test('a resolved job waiting for collection is not overdue', () {
      final j = job(
        status: ServiceJobStatus.resolved,
        promisedAt: DateTime(2026, 3, 2),
      );
      expect(j.isOverdue, isFalse);
    });
  });

  group('serialisation', () {
    test('round-trips through a map', () {
      final original = job(
        status: ServiceJobStatus.awaitingParts,
        warrantyUntil: DateTime(2026, 6, 1),
        promisedAt: DateTime(2026, 3, 15),
        parts: const [
          ServicePart(
            productId: 'p1',
            productName: 'Board',
            quantity: 1,
            unitPrice: 1500,
            issued: true,
          ),
        ],
        charges: const [ServiceCharge(label: 'Labour', amount: 500)],
      );
      final restored = ServiceJobModel.fromMap(original.toMap(), 'j1');
      expect(restored.status, ServiceJobStatus.awaitingParts);
      expect(restored.warrantyUntil, DateTime(2026, 6, 1));
      expect(restored.parts.single.issued, isTrue);
      expect(restored.charges.single.amount, 500);
      expect(restored.billableTotal, 2000);
    });

    test('the map carries the billable total for list rendering', () {
      final map = job(
        charges: const [ServiceCharge(label: 'Labour', amount: 250)],
      ).toMap();
      expect(map['billableTotal'], 250);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/recurring_invoice_model.dart';

void main() {
  final now = DateTime(2026, 3, 15);

  RecurringInvoiceModel schedule({
    RecurrenceCadence cadence = RecurrenceCadence.monthly,
    RecurringInvoiceStatus status = RecurringInvoiceStatus.active,
    DateTime? nextRunAt,
    DateTime? endDate,
    int maxOccurrences = 0,
    int generatedCount = 0,
  }) => RecurringInvoiceModel(
    id: 's1',
    customerId: 'c1',
    cadence: cadence,
    status: status,
    startDate: DateTime(2026, 1, 1),
    endDate: endDate,
    maxOccurrences: maxOccurrences,
    generatedCount: generatedCount,
    nextRunAt: nextRunAt ?? DateTime(2026, 3, 1),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('advance', () {
    test('steps by the cadence', () {
      final from = DateTime(2026, 1, 10);
      expect(
        RecurringInvoiceModel.advance(from, RecurrenceCadence.weekly),
        DateTime(2026, 1, 17),
      );
      expect(
        RecurringInvoiceModel.advance(from, RecurrenceCadence.fortnightly),
        DateTime(2026, 1, 24),
      );
      expect(
        RecurringInvoiceModel.advance(from, RecurrenceCadence.monthly),
        DateTime(2026, 2, 10),
      );
      expect(
        RecurringInvoiceModel.advance(from, RecurrenceCadence.quarterly),
        DateTime(2026, 4, 10),
      );
      expect(
        RecurringInvoiceModel.advance(from, RecurrenceCadence.yearly),
        DateTime(2027, 1, 10),
      );
    });

    test('clamps the day into a shorter month instead of overflowing it', () {
      // DateTime(2026, 2, 31) would silently become 3 March, moving the
      // billing date into the following month.
      expect(
        RecurringInvoiceModel.advance(
          DateTime(2026, 1, 31),
          RecurrenceCadence.monthly,
        ),
        DateTime(2026, 2, 28),
      );
      expect(
        RecurringInvoiceModel.advance(
          DateTime(2026, 3, 31),
          RecurrenceCadence.monthly,
        ),
        DateTime(2026, 4, 30),
      );
    });

    test('a monthly step crosses the year boundary', () {
      expect(
        RecurringInvoiceModel.advance(
          DateTime(2026, 12, 15),
          RecurrenceCadence.monthly,
        ),
        DateTime(2027, 1, 15),
      );
    });
  });

  group('isDue', () {
    test('is due once the run date has arrived', () {
      expect(
        schedule(nextRunAt: DateTime(2026, 3, 1)).isDue(asOf: now),
        isTrue,
      );
      expect(
        schedule(nextRunAt: DateTime(2026, 4, 1)).isDue(asOf: now),
        isFalse,
      );
    });

    test('is due on the day itself, whatever the time of day', () {
      // Compared on whole days: a schedule created at 4pm must not wait until
      // 4pm on its due date.
      expect(
        schedule(nextRunAt: DateTime(2026, 3, 15, 23, 0)).isDue(asOf: now),
        isTrue,
      );
    });

    test('a paused or ended schedule is never due', () {
      expect(
        schedule(status: RecurringInvoiceStatus.paused).isDue(asOf: now),
        isFalse,
      );
      expect(
        schedule(status: RecurringInvoiceStatus.ended).isDue(asOf: now),
        isFalse,
      );
    });

    test('a schedule past its occurrence cap is not due', () {
      expect(
        schedule(maxOccurrences: 3, generatedCount: 3).isDue(asOf: now),
        isFalse,
      );
      expect(
        schedule(maxOccurrences: 3, generatedCount: 2).isDue(asOf: now),
        isTrue,
      );
    });

    test('a schedule whose next run is past its end date is not due', () {
      expect(
        schedule(
          nextRunAt: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 2, 1),
        ).isDue(asOf: now),
        isFalse,
      );
    });

    test('days until due goes negative when overdue', () {
      expect(
        schedule(nextRunAt: DateTime(2026, 3, 10)).daysUntilDue(asOf: now),
        -5,
      );
      expect(
        schedule(nextRunAt: DateTime(2026, 3, 20)).daysUntilDue(asOf: now),
        5,
      );
    });
  });

  group('serialization', () {
    test('round-trips through a map', () {
      final original = schedule(cadence: RecurrenceCadence.quarterly);
      final restored = RecurringInvoiceModel.fromMap(original.toMap(), 's1');
      expect(restored.cadence, RecurrenceCadence.quarterly);
      expect(restored.nextRunAt, original.nextRunAt);
      expect(restored.status, RecurringInvoiceStatus.active);
    });
  });
}

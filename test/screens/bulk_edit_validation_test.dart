import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/screens/bulk/bulk_edit_validation.dart';

void main() {
  group('isValidThreshold', () {
    test('accepts zero, which means "never warn"', () {
      expect(isValidThreshold('0'), isTrue);
    });

    test('accepts a positive integer, with surrounding space', () {
      expect(isValidThreshold('12'), isTrue);
      expect(isValidThreshold('  12  '), isTrue);
    });

    test('rejects empty, null, negative and non-numeric', () {
      expect(isValidThreshold(null), isFalse);
      expect(isValidThreshold(''), isFalse);
      expect(isValidThreshold('   '), isFalse);
      expect(isValidThreshold('-1'), isFalse);
      expect(isValidThreshold('abc'), isFalse);
      expect(isValidThreshold('1.5'), isFalse);
    });
  });

  group('bulkEditMissingValues', () {
    test('a field nobody selected is never missing', () {
      expect(
        bulkEditMissingValues(selectedFields: const {}),
        isEmpty,
      );
    });

    test('a selected field with no value is reported', () {
      expect(
        bulkEditMissingValues(selectedFields: {BulkEditField.category}),
        ['Category'],
      );
      expect(
        bulkEditMissingValues(selectedFields: {BulkEditField.company}),
        ['Company / Brand'],
      );
      expect(
        bulkEditMissingValues(selectedFields: {BulkEditField.size}),
        ['Sub-Category'],
      );
      expect(
        bulkEditMissingValues(selectedFields: {BulkEditField.threshold}),
        ['Low Stock Threshold'],
      );
    });

    test('a selected field with a value is not reported', () {
      expect(
        bulkEditMissingValues(
          selectedFields: {BulkEditField.category},
          category: 'Beverages',
        ),
        isEmpty,
      );
      expect(
        bulkEditMissingValues(
          selectedFields: {BulkEditField.threshold},
          thresholdText: '0',
        ),
        isEmpty,
      );
    });

    test('the partial case — one field set, another not — is caught', () {
      // This is the defect the rule exists for. Applying used to write the
      // category, skip the unparseable threshold without a word, and report
      // full success.
      final missing = bulkEditMissingValues(
        selectedFields: {BulkEditField.category, BulkEditField.threshold},
        category: 'Beverages',
        thresholdText: 'not a number',
      );
      expect(missing, ['Low Stock Threshold']);
    });

    test('reports every missing field, in the wizard\'s order', () {
      final missing = bulkEditMissingValues(
        selectedFields: {
          BulkEditField.threshold,
          BulkEditField.size,
          BulkEditField.category,
          BulkEditField.company,
        },
      );
      expect(missing, [
        'Category',
        'Company / Brand',
        'Sub-Category',
        'Low Stock Threshold',
      ]);
    });

    test('a value for a field that was not selected is ignored', () {
      expect(
        bulkEditMissingValues(
          selectedFields: {BulkEditField.category},
          category: 'Beverages',
          thresholdText: 'rubbish',
        ),
        isEmpty,
      );
    });
  });

  group('bulkEditMissingValuesMessage', () {
    test('is empty when nothing is missing', () {
      expect(bulkEditMissingValuesMessage(const []), '');
    });

    test('reads naturally for one and for several', () {
      expect(
        bulkEditMissingValuesMessage(const ['Category']),
        'Set a value for Category',
      );
      expect(
        bulkEditMissingValuesMessage(const ['Category', 'Sub-Category']),
        'Set values for Category, Sub-Category',
      );
    });
  });
}

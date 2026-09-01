import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/screens/settings/settings_search.dart';

void main() {
  group('settingsEntryMatches', () {
    test('matches on the title, case-insensitively', () {
      expect(settingsEntryMatches('Manage Vendors', null, 'vendor'), isTrue);
      expect(settingsEntryMatches('Manage Vendors', null, 'VENDOR'), isTrue);
      expect(settingsEntryMatches('Manage Vendors', null, 'Manage'), isTrue);
    });

    test('matches on the subtitle', () {
      // "tax" and "numbering" appear only in the subtitle of Billing Settings,
      // so a title-only search would never find it.
      const sub = 'Company profile, tax, numbering & terms';
      expect(settingsEntryMatches('Billing Settings', sub, 'tax'), isTrue);
      expect(settingsEntryMatches('Billing Settings', sub, 'numbering'), isTrue);
    });

    test('does not match unrelated text', () {
      expect(
        settingsEntryMatches('Manage Vendors', 'Add and edit', 'invoice'),
        isFalse,
      );
    });

    test('a null subtitle is not a match and does not throw', () {
      expect(settingsEntryMatches('Appearance', null, 'theme'), isFalse);
    });

    test('an empty or whitespace query keeps everything', () {
      expect(settingsEntryMatches('Anything', null, ''), isTrue);
      expect(settingsEntryMatches('Anything', null, '   '), isTrue);
    });

    test('surrounding whitespace in the query is ignored', () {
      expect(settingsEntryMatches('Manage Vendors', null, '  vendor  '), isTrue);
    });
  });

  group('settingsSectionMatches', () {
    test('matches a section by its own name', () {
      // Typing "account" should keep the Account section entire, not just the
      // rows that happen to repeat the word.
      expect(settingsSectionMatches('Account', 'account'), isTrue);
      expect(settingsSectionMatches('Administration', 'admin'), isTrue);
    });

    test('does not match an unrelated section', () {
      expect(settingsSectionMatches('Appearance', 'vendor'), isFalse);
    });

    test('an empty query keeps every section', () {
      expect(settingsSectionMatches('Legal', ''), isTrue);
    });
  });
}

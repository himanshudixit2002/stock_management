import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('runs the action once after the delay', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        d.run(() => calls++);
        expect(calls, 0);
        async.elapse(const Duration(milliseconds: 99));
        expect(calls, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
      });
    });

    test('collapses a burst into the last call', () {
      fakeAsync((async) {
        final seen = <String>[];
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        d.run(() => seen.add('a'));
        async.elapse(const Duration(milliseconds: 50));
        d.run(() => seen.add('b'));
        async.elapse(const Duration(milliseconds: 50));
        d.run(() => seen.add('c'));
        async.elapse(const Duration(milliseconds: 100));
        expect(seen, ['c']);
      });
    });

    test('cancel drops a pending call', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        d.run(() => calls++);
        d.cancel();
        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
      });
    });

    test('dispose stops a pending call from firing after unmount', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        d.run(() => calls++);
        d.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
      });
    });

    test('isPending reflects whether a call is scheduled', () {
      fakeAsync((async) {
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        expect(d.isPending, isFalse);
        d.run(() {});
        expect(d.isPending, isTrue);
        async.elapse(const Duration(milliseconds: 100));
        expect(d.isPending, isFalse);
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/utils/currency.dart';

/// The one money-affecting decision on the dashboard: whether a total may be shown in the
/// user's base currency. An empty rate map must not.
void main() {
  group('ratesReadyFor', () {
    test('an empty rate map cannot render a converted total', () {
      expect(ratesReadyFor('USD', const {}), isFalse);
      expect(ratesReadyFor('USD', null), isFalse);
    });

    test('a populated rate map allows the conversion', () {
      expect(ratesReadyFor('USD', const {'PKR': 280}), isTrue);
    });

    test('PKR needs no rates — the figures are already in it', () {
      expect(ratesReadyFor('PKR', null), isTrue);
      expect(ratesReadyFor('PKR', const {}), isTrue);
    });
  });
}

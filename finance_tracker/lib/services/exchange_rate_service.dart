import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';

/// Fetches live exchange rates from the free open.er-api.com API.
///
/// The API returns rates as "1 baseCurrency = X targetCurrency".
/// We store rates as "1 targetCurrency = N baseCurrency" (the inverse),
/// because that's what the backend's SQL COALESCE expects.
class ExchangeRateService {
  static const _apiBase = 'https://open.er-api.com/v6/latest';

  /// Fetch exchange rates for all supported currencies relative to
  /// [baseCurrency]. Returns a map like `{'USD': 280, 'EUR': 300, ...}`
  /// meaning 1 USD = 280 baseCurrency units.
  ///
  /// Returns null if the fetch fails — callers should fall back to
  /// stored or default rates.
  static Future<Map<String, double>?> fetchRates(String baseCurrency) async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/$baseCurrency'));

      if (response.statusCode != 200) return null;

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['result'] != 'success') return null;

      final apiRates = body['rates'] as Map<String, dynamic>;
      final rates = <String, double>{};

      for (final currency in Constants.supportedCurrencies) {
        if (currency.code == baseCurrency) continue;

        final apiRate = apiRates[currency.code];
        if (apiRate == null) continue;

        final rateValue = (apiRate as num).toDouble();
        if (rateValue > 0) {
          // API gives "1 base = rateValue target".
          // We need "1 target = N base", so invert.
          rates[currency.code] = 1 / rateValue;
        }
      }

      return rates.isEmpty ? null : rates;
    } catch (_) {
      return null;
    }
  }
}

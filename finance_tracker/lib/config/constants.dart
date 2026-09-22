import 'package:flutter/foundation.dart';

/// App-wide constants: API configuration, fixed reference data, and storage keys.
class Constants {
  Constants._();

  /// The effective API base URL — returns the user-configured override
  /// if set, otherwise the platform default.
  static String get apiBaseUrl => _customApiBaseUrl ?? _defaultApiBaseUrl;

  /// Platform-default base URL.
  /// Android uses the ngrok public tunnel so the app works from any network
  /// (not just office WiFi). Web/desktop use localhost for local dev.
  static String get _defaultApiBaseUrl {
    if (kIsWeb) return 'http://localhost:5000/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'https://tributary-evergreen-repeater.ngrok-free.dev/api';
    }
    return 'http://localhost:5000/api';
  }

  /// User-configured override, hydrated from secure storage at startup.
  static String? _customApiBaseUrl;
  static bool get hasCustomApiBaseUrl => _customApiBaseUrl != null;
  static set customApiBaseUrl(String? url) => _customApiBaseUrl = url;

  static const String defaultCurrency = 'PKR';
  static const String defaultTimezone = 'Asia/Karachi';

  /// Currencies supported by the app. The user picks one in Settings and
  /// the entire app adapts — dashboard, transactions, budgets, receipts.
  static const List<Currency> supportedCurrencies = [
    Currency(code: 'PKR', name: 'Pakistani Rupee', symbol: '₨'),
    Currency(code: 'USD', name: 'US Dollar', symbol: '\$'),
    Currency(code: 'EUR', name: 'Euro', symbol: '€'),
    Currency(code: 'GBP', name: 'British Pound', symbol: '£'),
    Currency(code: 'AED', name: 'UAE Dirham', symbol: 'د.إ'),
    Currency(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
    Currency(code: 'SAR', name: 'Saudi Riyal', symbol: '﷼'),
    Currency(code: 'CAD', name: 'Canadian Dollar', symbol: 'C\$'),
    Currency(code: 'AUD', name: 'Australian Dollar', symbol: 'A\$'),
  ];

  /// Look up the symbol for a currency code. Falls back to the raw code
  /// if the code isn't in [supportedCurrencies].
  static String currencySymbol(String code) {
    for (final c in supportedCurrencies) {
      if (c.code == code) return c.symbol;
    }
    return code;
  }

  /// Default exchange rates relative to PKR (1 unit of X = N PKR).
  /// Used to pre-fill the Settings form when the base currency is PKR
  /// and the user hasn't set custom rates yet.
  static const Map<String, double> defaultRatesToPKR = {
    'USD': 280,
    'EUR': 300,
    'GBP': 350,
    'AED': 76,
    'INR': 3.3,
    'SAR': 75,
    'CAD': 200,
    'AUD': 185,
  };

  /// Payment sources seeded in the backend (no CRUD endpoint exists for these).
  static const List<Source> sources = [
    Source(id: 1, name: 'Card'),
    Source(id: 2, name: 'Cash'),
    Source(id: 3, name: 'Online'),
  ];

  // Secure storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String apiBaseUrlKey = 'api_base_url';
  static const String themeModeKey = 'theme_mode';
}

/// A fixed payment source (Card, Cash, Online).
class Source {
  final int id;
  final String name;

  const Source({required this.id, required this.name});
}

/// A supported currency with ISO code, display name, and symbol.
class Currency {
  final String code;
  final String name;
  final String symbol;

  const Currency({required this.code, required this.name, required this.symbol});
}

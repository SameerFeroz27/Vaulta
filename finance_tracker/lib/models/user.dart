/// User account data returned by the auth endpoints.
class User {
  final int id;
  final String email;
  final String name;
  final String currency;
  final String timezone;
  final String? status;

  /// Exchange rates relative to the base [currency].
  /// `{'USD': 280, 'EUR': 300, ...}` means 1 USD = 280 base currency units.
  /// Null when the user hasn't set any rates (single-currency mode).
  final Map<String, double>? exchangeRates;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.currency,
    required this.timezone,
    this.status,
    this.exchangeRates,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final rawRates = json['exchangeRates'] as Map<String, dynamic>?;
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String? ?? 'PKR',
      timezone: json['timezone'] as String? ?? 'Asia/Karachi',
      status: json['status'] as String?,
      exchangeRates: rawRates?.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

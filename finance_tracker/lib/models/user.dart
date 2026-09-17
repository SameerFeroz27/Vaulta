/// User account data returned by the auth endpoints.
class User {
  final int id;
  final String email;
  final String name;
  final String currency;
  final String timezone;
  final String? status;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.currency,
    required this.timezone,
    this.status,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String? ?? 'PKR',
      timezone: json['timezone'] as String? ?? 'Asia/Karachi',
      status: json['status'] as String?,
    );
  }
}

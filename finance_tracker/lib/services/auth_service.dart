import '../models/user.dart';
import 'api_client.dart';

/// Result of a successful login or register call.
class AuthResult {
  final User user;
  final String accessToken;
  final String refreshToken;

  AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });
}

/// Handles authentication API calls and response parsing.
class AuthService {
  final ApiClient apiClient;

  AuthService({required this.apiClient});

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final data = await apiClient.post(
      '/auth/register',
      body: {'name': name, 'email': email, 'password': password},
    );
    return _parse(data);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final data = await apiClient.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    return _parse(data);
  }

  Future<User> me() async {
    final data = await apiClient.get('/auth/me');
    return User.fromJson(data['user']);
  }

  Future<User> updateProfile({
    String? currency,
    String? timezone,
    String? name,
    Map<String, double>? exchangeRates,
    bool clearExchangeRates = false,
  }) async {
    final body = <String, dynamic>{};
    if (currency != null) body['currency'] = currency;
    if (timezone != null) body['timezone'] = timezone;
    if (name != null) body['name'] = name;
    if (clearExchangeRates) {
      body['exchangeRates'] = null;
    } else if (exchangeRates != null) {
      body['exchangeRates'] = exchangeRates;
    }
    final data = await apiClient.put('/auth/me', body: body);
    return User.fromJson(data['user']);
  }

  Future<void> logout(String refreshToken) async {
    await apiClient.post('/auth/logout', body: {'refreshToken': refreshToken});
  }

  Future<void> requestPasswordReset(String email) async {
    await apiClient.post(
      '/auth/forgot-password',
      body: {'email': email},
    );
  }

  Future<void> resetPassword(String token, String newPassword) async {
    await apiClient.post(
      '/auth/reset-password',
      body: {'token': token, 'password': newPassword},
    );
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await apiClient.put(
      '/auth/me/password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  AuthResult _parse(Map<String, dynamic> data) {
    final tokens = data['tokens'] as Map<String, dynamic>;
    return AuthResult(
      user: User.fromJson(data['user']),
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
    );
  }
}

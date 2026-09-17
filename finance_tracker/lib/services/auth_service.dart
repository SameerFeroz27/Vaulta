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
  }) async {
    final body = <String, dynamic>{};
    if (currency != null) body['currency'] = currency;
    if (timezone != null) body['timezone'] = timezone;
    if (name != null) body['name'] = name;
    final data = await apiClient.put('/auth/me', body: body);
    return User.fromJson(data['user']);
  }

  Future<void> logout(String refreshToken) async {
    await apiClient.post('/auth/logout', body: {'refreshToken': refreshToken});
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

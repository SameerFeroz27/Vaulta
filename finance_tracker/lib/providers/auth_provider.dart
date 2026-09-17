import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Manages authentication state: current user, login/register/logout flows,
/// and initialization from stored tokens.
class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  late final AuthService _authService;
  final List<VoidCallback> _resetCallbacks = [];

  AuthProvider({required ApiClient apiClient}) : _apiClient = apiClient {
    _authService = AuthService(apiClient: apiClient);
  }

  /// Register a provider reset callback — called on login, register, and logout
  /// to clear cached data from a previous user's session.
  void registerResetCallback(VoidCallback callback) {
    _resetCallbacks.add(callback);
  }

  void _resetDependents() {
    for (final cb in _resetCallbacks) {
      cb();
    }
  }

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _isLoading = false;
  String? _error;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// On app start: validate stored tokens by calling /auth/me.
  Future<void> init() async {
    if (!_apiClient.isAuthenticated) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      _user = await _authService.me();
      _status = AuthStatus.authenticated;
    } catch (_) {
      await _apiClient.clearTokens();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.login(email: email, password: password);
      await _apiClient.saveTokens(result.accessToken, result.refreshToken);
      _user = result.user;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _resetDependents();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'An unexpected error occurred. Please try again.';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.register(
        name: name,
        email: email,
        password: password,
      );
      await _apiClient.saveTokens(result.accessToken, result.refreshToken);
      _user = result.user;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _resetDependents();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'An unexpected error occurred. Please try again.';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    final refreshToken = _apiClient.refreshToken;
    if (refreshToken != null) {
      try {
        await _authService.logout(refreshToken);
      } catch (_) {}
    }
    await _apiClient.clearTokens();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _error = null;
    _resetDependents();
    notifyListeners();
  }

  /// Called when token refresh fails — redirects to login without an API call.
  void forceLogout() {
    _user = null;
    _status = AuthStatus.unauthenticated;
    _resetDependents();
    notifyListeners();
  }

  /// Update the user's profile (currency, timezone, name).
  Future<void> updateProfile({
    String? currency,
    String? timezone,
    String? name,
  }) async {
    try {
      _user = await _authService.updateProfile(
        currency: currency,
        timezone: timezone,
        name: name,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }
}

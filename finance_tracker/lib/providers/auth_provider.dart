import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/exchange_rate_service.dart';

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
  ///
  /// We only clear tokens when the server definitively rejects them
  /// (UNAUTHORIZED).  A TOKEN_EXPIRED error means the access token expired
  /// and [_tryRefresh] already handled it — either clearing tokens if the
  /// refresh was rejected, or keeping them if the network failed.  A network
  /// error means we simply couldn't reach the server; the tokens may still
  /// be valid, so we keep them and show the login screen as a fallback.
  Future<void> init() async {
    if (!_apiClient.isAuthenticated) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      _user = await _authService.me();
      _status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        await _apiClient.clearTokens();
      }
      _status = AuthStatus.unauthenticated;
    } catch (_) {
      // Network error or other transient failure — keep tokens in
      // storage so the next app start can retry.
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();

    // Auto-fetch exchange rates in the background if missing
    if (_status == AuthStatus.authenticated &&
        (_user?.exchangeRates?.isEmpty ?? true)) {
      refreshExchangeRates();
    }
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

  /// Update the user's profile (currency, timezone, name, exchangeRates).
  /// Returns true on success, false on failure (error is set in [error]).
  Future<bool> updateProfile({
    String? currency,
    String? timezone,
    String? name,
    Map<String, double>? exchangeRates,
    bool clearExchangeRates = false,
  }) async {
    _error = null;
    try {
      _user = await _authService.updateProfile(
        currency: currency,
        timezone: timezone,
        name: name,
        exchangeRates: exchangeRates,
        clearExchangeRates: clearExchangeRates,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Fetch live exchange rates for the user's base currency from the API
  /// and save them to the backend. Returns true on success.
  /// Call this when the base currency changes or when rates are missing.
  Future<bool> refreshExchangeRates() async {
    if (_user == null) return false;

    final baseCurrency = _user!.currency;
    final rates = await ExchangeRateService.fetchRates(baseCurrency);
    if (rates == null) {
      _error = 'Could not fetch exchange rates. Check your connection.';
      notifyListeners();
      return false;
    }

    return updateProfile(exchangeRates: rates);
  }

  /// Request a password reset OTP for the given email.
  /// The backend sends a 6-digit code to the user's email.
  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.requestPasswordReset(email);
      _isLoading = false;
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

  /// Reset password using a reset token and new password.
  Future<bool> resetPassword(String token, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.resetPassword(token, newPassword);
      _isLoading = false;
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

  /// Change password for the currently authenticated user.
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.changePassword(currentPassword, newPassword);
      _isLoading = false;
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
}

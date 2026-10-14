import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/constants.dart';

/// Custom exception wrapping the backend's error envelope:
/// `{ success: false, error: { code, message, details } }`
class ApiException implements Exception {
  final String code;
  final String message;
  final List<dynamic>? details;

  ApiException({required this.code, required this.message, this.details});

  @override
  String toString() => message;
}

/// HTTP client that handles auth headers, automatic token refresh on
/// 401 TOKEN_EXPIRED, and unwrapping the `{ success, data }` envelope.
///
/// Dependencies are injected so tests can pass a [MockClient] and a mock
/// [FlutterSecureStorage] instead of hitting the real network and keystore.
class ApiClient {
  final http.Client _httpClient;
  final FlutterSecureStorage _storage;

  ApiClient({http.Client? httpClient, FlutterSecureStorage? storage})
    : _httpClient = httpClient ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;

  /// Whether the current session is written to secure storage. Held so a token refresh
  /// during a non-persistent session does not quietly persist it behind the user's back.
  bool _persistSession = true;

  /// Called when token refresh fails so the app can redirect to login.
  void Function()? onAuthFailed;

  /// Load tokens and API base URL override from secure storage on app start.
  Future<void> init() async {
    _accessToken = await _storage.read(key: Constants.accessTokenKey);
    _refreshToken = await _storage.read(key: Constants.refreshTokenKey);
    Constants.customApiBaseUrl =
        await _storage.read(key: Constants.apiBaseUrlKey);
  }

  /// Persist both tokens to memory, and to secure storage unless [persist] is false.
  ///
  /// A session with [persist] false lives in memory only, so leaving "Keep me signed in"
  /// unticked means the next app start asks for credentials again.
  Future<void> saveTokens(
    String accessToken,
    String refreshToken, {
    bool persist = true,
  }) async {
    _persistSession = persist;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (!persist) return;
    await _storage.write(key: Constants.accessTokenKey, value: accessToken);
    await _storage.write(key: Constants.refreshTokenKey, value: refreshToken);
  }

  /// Clear tokens from memory and storage (logout / refresh failure).
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: Constants.accessTokenKey);
    await _storage.delete(key: Constants.refreshTokenKey);
  }

  /// Persist a custom API base URL override to secure storage.
  Future<void> saveApiBaseUrl(String url) async {
    await _storage.write(key: Constants.apiBaseUrlKey, value: url);
    Constants.customApiBaseUrl = url;
  }

  /// Clear the custom override and revert to the platform default.
  Future<void> resetApiBaseUrl() async {
    await _storage.delete(key: Constants.apiBaseUrlKey);
    Constants.customApiBaseUrl = null;
  }

  bool get isAuthenticated => _accessToken != null;
  String? get refreshToken => _refreshToken;

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  dynamic _unwrap(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Not our envelope: an HTML error page from a tunnel or proxy, a wrong base URL,
      // or an empty body. Without this the JSON decode fails with a FormatException that
      // says nothing about what actually went wrong.
      throw ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected response from the server (HTTP ${response.statusCode}). '
            'Check the backend URL in Settings and that the server is running.',
      );
    }

    if (body['success'] == true) {
      return body['data'];
    }

    final error = body['error'];
    if (error is! Map<String, dynamic>) {
      throw ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an error without details (HTTP ${response.statusCode}).',
      );
    }

    throw ApiException(
      code: error['code'] as String? ?? 'UNKNOWN_ERROR',
      message: error['message'] as String? ?? 'An unknown error occurred',
      details: error['details'] as List<dynamic>?,
    );
  }

  /// Attempt to refresh the access token using the stored refresh token.
  /// Returns true on success, false on failure.
  ///
  /// On a *network* failure we return false WITHOUT clearing tokens — the
  /// refresh token may still be valid, so the next request can retry.  We
  /// only clear tokens when the server explicitly rejects the refresh token
  /// (success: false), meaning the credentials are genuinely invalid.
  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;

    http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse('${Constants.apiBaseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refreshToken': _refreshToken}),
      );
    } catch (_) {
      // Network error — keep tokens; they may still be valid.
      return false;
    }

    Map<String, dynamic> body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Non-JSON response (e.g. ngrok error page) — keep tokens.
      return false;
    }

    if (body['success'] == true) {
      final tokens = body['data']['tokens'] as Map<String, dynamic>;
      await saveTokens(
        tokens['accessToken'] as String,
        tokens['refreshToken'] as String,
        // Keep the session's own choice: a refresh must not start persisting a session the
        // user chose to keep only for this run.
        persist: _persistSession,
      );
      return true;
    }

    // Server explicitly rejected the refresh token — credentials are invalid.
    await clearTokens();
    onAuthFailed?.call();
    return false;
  }

  /// Send a request, retrying it once with a fresh access token when the
  /// server responds 401 TOKEN_EXPIRED. The [send] callback is re-invoked
  /// after a successful refresh so the new token lands in the headers.
  Future<http.Response> _withRefreshRetry(
    Future<http.Response> Function() send,
  ) async {
    var response = await send();

    if (response.statusCode == 401) {
      try {
        final errorBody = json.decode(response.body) as Map<String, dynamic>;
        if (errorBody['error']?['code'] == 'TOKEN_EXPIRED') {
          if (await _tryRefresh()) {
            response = await send();
          }
        }
      } catch (_) {
        // response body wasn't JSON; let _unwrap handle it
      }
    }

    return response;
  }

  Future<dynamic> get(String endpoint, {Map<String, dynamic>? query}) {
    return _request('GET', endpoint, query: query);
  }

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) {
    return _request('POST', endpoint, body: body);
  }

  Future<dynamic> put(String endpoint, {Map<String, dynamic>? body}) {
    return _request('PUT', endpoint, body: body);
  }

  Future<dynamic> delete(String endpoint) {
    return _request('DELETE', endpoint);
  }

  /// Send a multipart/form-data POST (for file uploads).
  ///
  /// [fieldName] is the form field name for the file, [fileBytes] is the
  /// raw file content, [filename] is the file name to send, and [fields]
  /// are optional text form fields sent alongside the file.
  Future<dynamic> multipartPost(
    String endpoint, {
    required String fieldName,
    required Uint8List fileBytes,
    required String filename,
    String? contentType,
    Map<String, String> fields = const {},
  }) async {
    final uri = Uri.parse('${Constants.apiBaseUrl}$endpoint');

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', uri);
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          fileBytes,
          filename: filename,
          contentType: contentType != null
              ? MediaType.parse(contentType)
              : null,
        ),
      );
      final streamedResponse = await _httpClient.send(request);
      return http.Response.fromStream(streamedResponse);
    }

    final response = await _withRefreshRetry(send);
    return _unwrap(response);
  }

  Future<dynamic> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    var uri = Uri.parse('${Constants.apiBaseUrl}$endpoint');
    if (query != null) {
      final params = <String, String>{};
      query.forEach((k, v) {
        if (v != null) params[k] = v.toString();
      });
      uri = uri.replace(queryParameters: params);
    }

    Future<http.Response> send() {
      switch (method) {
        case 'GET':
          return _httpClient.get(uri, headers: _headers());
        case 'POST':
          return _httpClient.post(
            uri,
            headers: _headers(),
            body: body != null ? json.encode(body) : null,
          );
        case 'PUT':
          return _httpClient.put(
            uri,
            headers: _headers(),
            body: body != null ? json.encode(body) : null,
          );
        case 'DELETE':
          return _httpClient.delete(uri, headers: _headers());
        default:
          throw ApiException(
            code: 'INVALID_METHOD',
            message: 'Unsupported HTTP method: $method',
          );
      }
    }

    final response = await _withRefreshRetry(send);
    return _unwrap(response);
  }
}

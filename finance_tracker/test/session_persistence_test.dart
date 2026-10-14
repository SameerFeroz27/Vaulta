import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:finance_tracker/services/api_client.dart';

/// "Keep me signed in" left unticked must keep the session in memory only — including across
/// a token refresh — so the next app start asks for credentials again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> vault;

  setUp(() {
    vault = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      switch (call.method) {
        case 'write':
          vault[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return vault[args['key'] as String];
        case 'containsKey':
          return vault.containsKey(args['key'] as String);
        case 'delete':
          vault.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          vault.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(vault);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a ticked session survives a restart', () async {
    final first = ApiClient();
    await first.saveTokens('access', 'refresh');

    final next = ApiClient();
    await next.init();

    expect(next.isAuthenticated, isTrue);
    expect(vault, isNotEmpty);
  });

  test('an unticked session is not written to storage', () async {
    final first = ApiClient();
    await first.saveTokens('access', 'refresh', persist: false);

    // Usable for this run, but nothing is left behind for the next.
    expect(first.isAuthenticated, isTrue);
    expect(vault, isEmpty);

    final next = ApiClient();
    await next.init();
    expect(next.isAuthenticated, isFalse);
  });

  test('a refresh during an unticked session does not start persisting it', () async {
    var refreshCalls = 0;
    final client = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          return _json({
            'success': true,
            'data': {
              'tokens': {
                'accessToken': 'access-2',
                'refreshToken': 'refresh-2',
              },
            },
          });
        }
        // Every other call reports the access token as expired, forcing a refresh.
        return _json({
          'success': false,
          'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
        }, status: 401);
      }),
    );

    await client.saveTokens('access-1', 'refresh-1', persist: false);

    await expectLater(
      client.get('/transactions'),
      throwsA(isA<ApiException>()),
    );

    expect(refreshCalls, 1, reason: 'the refresh path must have run');
    expect(vault, isEmpty, reason: 'a refresh must not persist the session');
  });
}

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

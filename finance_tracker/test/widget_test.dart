import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/providers/auth_provider.dart';
import 'package:finance_tracker/providers/theme_provider.dart';
import 'package:finance_tracker/services/api_client.dart';

void main() {
  testWidgets('App renders login screen when unauthenticated', (
    WidgetTester tester,
  ) async {
    final apiClient = ApiClient();
    final authProvider = AuthProvider(apiClient: apiClient);
    final themeProvider = ThemeProvider();

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Login'))),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: FinanceTrackerApp(router: router),
      ),
    );

    expect(find.text('Login'), findsOneWidget);
  });
}

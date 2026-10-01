import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/category_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/loan_provider.dart';
import 'providers/receipt_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/loans/loan_list_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/transaction_list_screen.dart';
import 'services/api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient();
  await apiClient.init();

  final authProvider = AuthProvider(apiClient: apiClient);
  apiClient.onAuthFailed = authProvider.forceLogout;
  authProvider.init();

  final categoryProvider = CategoryProvider(apiClient: apiClient);
  final transactionProvider = TransactionProvider(apiClient: apiClient);
  final dashboardProvider = DashboardProvider(apiClient: apiClient);
  final receiptProvider = ReceiptProvider(apiClient: apiClient);
  final themeProvider = ThemeProvider();
  await themeProvider.init();

  final budgetProvider = BudgetProvider(apiClient: apiClient);
  final loanProvider = LoanProvider(apiClient: apiClient);

  // Refresh dashboard and budgets automatically when transactions change.
  transactionProvider.setDependents(dashboardProvider, budgetProvider);

  // Loan money movements land in the transactions ledger, so keep it in step.
  loanProvider.setDependents(transactionProvider);

  // Clear all cached data when the authenticated user changes.
  authProvider.registerResetCallback(transactionProvider.reset);
  authProvider.registerResetCallback(dashboardProvider.reset);
  authProvider.registerResetCallback(categoryProvider.reset);
  authProvider.registerResetCallback(receiptProvider.reset);
  authProvider.registerResetCallback(budgetProvider.reset);
  authProvider.registerResetCallback(loanProvider.reset);

  final router = GoRouter(
    refreshListenable: authProvider,
    initialLocation: '/',
    redirect: (context, state) {
      final status = authProvider.status;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/reset-password';

      if (status == AuthStatus.unknown) return null;
      if (status == AuthStatus.unauthenticated && !isAuthRoute) {
        return '/login';
      }
      if (status == AuthStatus.authenticated && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const MainScaffold()),
    ],
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<CategoryProvider>.value(value: categoryProvider),
        ChangeNotifierProvider<TransactionProvider>.value(
          value: transactionProvider,
        ),
        ChangeNotifierProvider<DashboardProvider>.value(
          value: dashboardProvider,
        ),
        ChangeNotifierProvider<ReceiptProvider>.value(value: receiptProvider),
        ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
        ChangeNotifierProvider<LoanProvider>.value(value: loanProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: FinanceTrackerApp(router: router),
    ),
  );
}

class FinanceTrackerApp extends StatelessWidget {
  final GoRouter router;

  const FinanceTrackerApp({required this.router, super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      title: 'Vaulta - Finance Tracking App',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

/// Bottom navigation scaffold with four tabs.
/// Shows a loading indicator while auth status is unknown.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  static const int _dashboardTabIndex = 0;
  static const int _loansTabIndex = 2;

  int _currentIndex = 0;

  /// Refresh the dashboard on arrival. It aggregates everything, so its figures would
  /// otherwise stay at whatever was loaded at app start and go stale the moment
  /// transactions or loans change on another tab.
  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);

    if (index == _dashboardTabIndex) {
      context.read<DashboardProvider>().loadDashboard();
      context.read<LoanProvider>().loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      // The dashboard's loans card jumps to the Loans tab.
      DashboardScreen(
        onOpenLoans: () => setState(() => _currentIndex = _loansTabIndex),
      ),
      const TransactionListScreen(),
      const LoanListScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        sizing: StackFit.expand,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        // Defaults to shifting (labels hidden) at 4+ items; all four should stay labelled.
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handshake_outlined),
            label: 'Loans',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/motion.dart';
import '../../config/theme.dart';
import '../../models/dashboard_summary.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/loan_provider.dart';
import '../../utils/currency.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/dashboard/expense_bar_chart.dart';
import '../../widgets/dashboard/expense_pie_chart.dart';
import '../../widgets/dashboard/loans_card.dart';
import '../../widgets/dashboard/summary_card.dart';
import '../../widgets/dashboard/tile_detail.dart';
import '../../widgets/motion/open_tile.dart';
import '../transactions/transaction_form_screen.dart';
import '../../widgets/motion/full_motion_route.dart';

class DashboardScreen extends StatefulWidget {
  /// Switches the shell to the Loans tab, so the loans detail's "See all loans" can land
  /// there.
  final VoidCallback? onOpenLoans;

  const DashboardScreen({this.onOpenLoans, super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
      context.read<LoanProvider>().loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final auth = context.watch<AuthProvider>();
    final loans = context.watch<LoanProvider>();
    final userCurrency = auth.user?.currency ?? 'PKR';

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          // Captured before the await: the context may be gone once it completes.
          final loanProvider = context.read<LoanProvider>();
          await provider.loadDashboard();
          await loanProvider.loadSummary();
        },
        child: _buildBody(provider, userCurrency, loans, auth),
      ),
    );
  }

  Widget _buildBody(
    DashboardProvider provider,
    String userCurrency,
    LoanProvider loans,
    AuthProvider auth,
  ) {
    if (provider.isLoading && provider.summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.summary == null) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  provider.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: provider.loadDashboard,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final summary = provider.summary;

    // The backend converts every aggregate into the base currency with a 1:1 fallback when
    // a rate is missing, so an empty rate map silently labels PKR figures with the new
    // symbol. Rather than show a figure that is quietly wrong, ask for the rates first.
    final ratesReady = ratesReadyFor(userCurrency, auth.user?.exchangeRates);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Month selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: provider.previousMonth,
              ),
              Text(
                Formatters.month(provider.month),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: provider.nextMonth,
              ),
            ],
          ),
        ),

        if (!ratesReady)
          _RatesNeededCard(
            currency: userCurrency,
            onFetch: () async {
              await auth.refreshExchangeRates();
              if (!mounted) return;
              await provider.loadDashboard();
            },
          )
        else if (summary != null) ...[
          // Empty state for new users with no transactions
          if (summary.transactionCount == 0) ...[
            const SizedBox(height: 40),
            EmptyState(
              icon: Icons.insights_outlined,
              title: 'Welcome to your dashboard',
              subtitle: 'Add your first transaction to see spending insights, charts, and budgets here.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  FullMotionPageRoute(
                    builder: (_) => const TransactionFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Transaction'),
              ),
            ),
            // Loans are independent of transactions, so they show here too.
            _buildLoansSection(loans, userCurrency, auth),
          ] else ...[
            // Summary cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _incomeTile(summary, provider, userCurrency),
                  ),
                  Expanded(
                    child: _expenseTile(summary, provider, userCurrency),
                  ),
                  Expanded(
                    child: _balanceTile(summary, userCurrency),
                  ),
                ],
              ),
            ),

            // Transaction count
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  '${summary.transactionCount} transactions',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),

            // Lending position sits directly under the income/expense/balance tiles.
            _buildLoansSection(loans, userCurrency, auth),
            const SizedBox(height: 8),

            // Expense by Category
            if (provider.categoryBreakdown != null)
              _categoryChart(provider, userCurrency),

            // Expense by Source
            if (provider.sourceBreakdown != null)
              _sourceChart(provider, userCurrency),

            // Expense Trend
            if (provider.trend != null && provider.trend!.data.isNotEmpty)
              RepaintBoundary(child: ExpenseBarChart(trend: provider.trend!)),

            // Top Merchants
            if (summary.topMerchants.isNotEmpty)
              _topMerchants(summary, userCurrency),
          ],
        ],
      ],
    );
  }

  // ---- Tiles that grow into their own detail -------------------------------------------
  //
  // Each detail mirrors the rows out of the tile that was tapped, so a detail can never
  // disagree with the card it came from.

  Widget _incomeTile(
    DashboardSummary summary,
    DashboardProvider provider,
    String userCurrency,
  ) {
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      tileBuilder: (context, open) => SummaryCard(
        label: 'Income',
        amount: summary.totalIncome,
        color: AppTheme.incomeFor(context),
        icon: Icons.arrow_upward,
        currency: userCurrency,
        margin: EdgeInsets.zero,
        onTap: open,
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Income',
        heroAmount: Formatters.currency(summary.totalIncome, code: userCurrency),
        heroLabel: 'this month',
        heroColor: AppTheme.incomeFor(context),
        rows: [
          TileDetailRow('Month', Formatters.month(provider.month)),
          TileDetailRow('Transactions', '${summary.transactionCount}'),
        ],
        note: 'Every income row for the month, added up.',
      ),
    );
  }

  Widget _expenseTile(
    DashboardSummary summary,
    DashboardProvider provider,
    String userCurrency,
  ) {
    final breakdown = provider.categoryBreakdown;
    final categoryRows = <TileDetailRow>[
      if (breakdown != null)
        for (final item in breakdown.items.where((i) => i.total > 0))
          TileDetailRow(
            item.icon != null ? '${item.icon} ${item.name}' : item.name,
            Formatters.currency(item.total, code: userCurrency),
            valueColor: AppTheme.expenseFor(context),
          ),
    ];

    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      tileBuilder: (context, open) => SummaryCard(
        label: 'Expense',
        amount: summary.totalExpense,
        color: AppTheme.expenseFor(context),
        icon: Icons.arrow_downward,
        currency: userCurrency,
        margin: EdgeInsets.zero,
        onTap: open,
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Expense',
        heroAmount: Formatters.currency(summary.totalExpense, code: userCurrency),
        heroLabel: 'this month',
        heroColor: AppTheme.expenseFor(context),
        rows: categoryRows,
        note: categoryRows.isEmpty
            ? 'No expenses recorded this month yet.'
            : 'Broken down by category.',
      ),
    );
  }

  Widget _balanceTile(DashboardSummary summary, String userCurrency) {
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      tileBuilder: (context, open) => SummaryCard(
        label: 'Balance',
        amount: summary.balance,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.account_balance_wallet_outlined,
        currency: userCurrency,
        margin: EdgeInsets.zero,
        onTap: open,
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Balance',
        heroAmount: Formatters.currency(summary.balance, code: userCurrency),
        heroLabel: 'left this month',
        heroColor: Theme.of(context).colorScheme.primary,
        rows: [
          TileDetailRow(
            'Income in',
            Formatters.currency(summary.totalIncome, code: userCurrency),
            valueColor: AppTheme.incomeFor(context),
          ),
          TileDetailRow(
            'Expense out',
            Formatters.currency(summary.totalExpense, code: userCurrency),
            valueColor: AppTheme.expenseFor(context),
          ),
          TileDetailRow(
            'Left over',
            Formatters.currency(summary.balance, code: userCurrency),
            valueColor: Theme.of(context).colorScheme.primary,
            bold: true,
          ),
        ],
      ),
    );
  }

  /// The lending section, or nothing at all when there is no lending to report —
  /// an empty card would be noise.
  Widget _buildLoansSection(
    LoanProvider loans,
    String userCurrency,
    AuthProvider auth,
  ) {
    if (loans.totalTheyOwe <= 0 && loans.totalIOwe <= 0 && loans.overdueCount <= 0) {
      return const SizedBox.shrink();
    }

    final rates = auth.user?.exchangeRates;
    final they = _convertLoans(loans.totalTheyOwe, userCurrency, rates);
    final iOwe = _convertLoans(loans.totalIOwe, userCurrency, rates);

    return OpenTile(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      tileBuilder: (context, open) => LoansCard(
        theyOwe: loans.totalTheyOwe,
        iOwe: loans.totalIOwe,
        overdueCount: loans.overdueCount,
        overduePeople: loans.overduePeople,
        currency: userCurrency,
        exchangeRates: rates,
        margin: EdgeInsets.zero,
        onTap: open,
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Loans',
        rows: [
          TileDetailRow(
            'Owed to me',
            Formatters.currency(they.amount, code: they.code),
            valueColor: AppTheme.incomeFor(context),
          ),
          TileDetailRow(
            'I owe',
            Formatters.currency(iOwe.amount, code: iOwe.code),
            valueColor: AppTheme.expenseFor(context),
          ),
          if (loans.overdueCount > 0)
            TileDetailRow(
              'Overdue',
              _overdueLabel(loans),
              valueColor: AppTheme.expenseFor(context),
              bold: true,
            ),
        ],
        actionLabel: 'See all loans',
        // The detail is dismissed first and the tab switch waits for the collapse, so the
        // two transitions never animate at once.
        onAction: () {
          Navigator.of(context).pop();
          Future.delayed(
            Motion.collapse,
            () => widget.onOpenLoans?.call(),
          );
        },
        note: 'Loans are tracked per person and stay in PKR.',
      ),
    );
  }

  Widget _categoryChart(DashboardProvider provider, String userCurrency) {
    final breakdown = provider.categoryBreakdown!;
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // The boundary keeps the custom-painted chart out of the repaint of everything around
      // it — the single heaviest widget on the screen.
      tileBuilder: (context, open) => RepaintBoundary(
        child: ExpensePieChart(
          title: 'Expenses by Category',
          breakdown: breakdown,
          currency: userCurrency,
          margin: EdgeInsets.zero,
          onTap: open,
        ),
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Expenses by Category',
        heroAmount: Formatters.currency(
          breakdown.totalExpense,
          code: userCurrency,
        ),
        heroLabel: 'this month',
        heroColor: AppTheme.expenseFor(context),
        rows: [
          for (final item in breakdown.items.where((i) => i.total > 0))
            TileDetailRow(
              item.icon != null ? '${item.icon} ${item.name}' : item.name,
              Formatters.currency(item.total, code: userCurrency),
              valueColor: AppTheme.expenseFor(context),
            ),
        ],
      ),
    );
  }

  Widget _sourceChart(DashboardProvider provider, String userCurrency) {
    final breakdown = provider.sourceBreakdown!;
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileBuilder: (context, open) => RepaintBoundary(
        child: ExpensePieChart(
          title: 'Expenses by Source',
          breakdown: breakdown,
          currency: userCurrency,
          margin: EdgeInsets.zero,
          onTap: open,
        ),
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Expenses by Source',
        heroAmount: Formatters.currency(
          breakdown.totalExpense,
          code: userCurrency,
        ),
        heroLabel: 'this month',
        heroColor: AppTheme.expenseFor(context),
        rows: [
          for (final item in breakdown.items.where((i) => i.total > 0))
            TileDetailRow(
              item.name,
              Formatters.currency(item.total, code: userCurrency),
              valueColor: AppTheme.expenseFor(context),
            ),
        ],
      ),
    );
  }

  Widget _topMerchants(DashboardSummary summary, String userCurrency) {
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileBuilder: (context, open) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top Merchants',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ...summary.topMerchants.map<Widget>(
                  (m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            m.merchant,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formatters.currency(m.totalSpent, code: userCurrency),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.expenseFor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      detailBuilder: (context) => TileDetailScreen(
        title: 'Top Merchants',
        rows: [
          for (final m in summary.topMerchants)
            TileDetailRow(
              m.merchant,
              Formatters.currency(m.totalSpent, code: userCurrency),
              valueColor: AppTheme.expenseFor(context),
            ),
        ],
      ),
    );
  }

  /// Returns the display amount and the currency code it is actually in. Loans are PKR at
  /// rest, so a non-PKR base converts them only when a rate is present.
  ({double amount, String code}) _convertLoans(
    double pkr,
    String currency,
    Map<String, double>? rates,
  ) {
    if (currency == 'PKR') return (amount: pkr, code: 'PKR');
    final rate = rates?['PKR'];
    if (rate != null && rate > 0) return (amount: pkr * rate, code: currency);
    return (amount: pkr, code: 'PKR');
  }

  String _overdueLabel(LoanProvider loans) {
    final people = loans.overduePeople;
    if (people.isEmpty) {
      return loans.overdueCount == 1
          ? '1 overdue'
          : '${loans.overdueCount} overdue';
    }
    if (people.length == 1) return people.first;
    return '${people.first}, +${people.length - 1} more';
  }
}

/// Shown in place of the totals when the base currency is set but no rates have arrived.
/// PKR needs no conversion, so this never appears for the default currency.
class _RatesNeededCard extends StatelessWidget {
  final String currency;
  final Future<void> Function() onFetch;

  const _RatesNeededCard({required this.currency, required this.onFetch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.currency_exchange_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Exchange rates needed',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your base currency is $currency, so every total has to be converted before '
              'it can be shown. Fetch the rates to continue.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onFetch,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Fetch exchange rates'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/loans/loan_filter_sheet.dart';
import '../../widgets/loans/loan_list_view.dart';
import '../../widgets/loans/loan_person_summary_view.dart';
import 'loan_detail_screen.dart';
import 'loan_form_screen.dart';

/// The Loans feature, split into two tabs.
///
/// The per-person summary gets its own tab rather than sitting above the list: it
/// aggregates by person while the list is per loan, and it counts removed loans, so
/// the two sets of figures do not reconcile and side by side they read as a
/// contradiction.
class LoanListScreen extends StatefulWidget {
  const LoanListScreen({super.key});

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen>
    with SingleTickerProviderStateMixin {
  static const int _summaryTabIndex = 1;

  late final TabController _tabController = TabController(length: 2, vsync: this);

  /// Tracked separately because [TabController] notifies on every animation tick;
  /// rebuilding for each of those would rebuild the list for no reason.
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LoanProvider>();
      // Both tabs read the same provider, so load once here rather than from whichever
      // tab happens to build first.
      if (provider.loans.isEmpty &&
          provider.summary.isEmpty &&
          !provider.isLoading) {
        provider.loadLoans();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index != _activeTabIndex) {
      setState(() => _activeTabIndex = _tabController.index);
    }
  }

  Future<void> _openFilters() async {
    final provider = context.read<LoanProvider>();
    final result = await showModalBottomSheet<LoanFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LoanFilterSheet(currentFilters: provider.filters),
    );
    if (result != null && mounted) {
      provider.setFilters(result);
    }
  }

  Future<void> _openForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoanFormScreen()),
    );
  }

  Future<void> _openDetail(Loan loan) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.id)),
    );
    // Repayments may have been added or deleted while the detail screen was open.
    if (mounted) await context.read<LoanProvider>().loadLoans();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        actions: [
          // Filtering narrows the loan list, so it is only offered on that tab.
          if (_activeTabIndex != _summaryTabIndex)
            IconButton(
              icon: const Icon(Icons.filter_list_outlined),
              onPressed: _openFilters,
              tooltip: 'Filters',
            ),
        ],
        // Two tabs, split evenly: the Material 3 default for a non-scrollable bar.
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Loans'),
            Tab(text: 'By person'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // An overdue loan matters on either tab, so the banner sits above both.
          if (provider.overdueCount > 0) _buildOverdueBanner(provider),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                LoanListView(onAddLoan: _openForm, onOpenLoan: _openDetail),
                LoanPersonSummaryView(onAddLoan: _openForm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverdueBanner(LoanProvider provider) {
    final count = provider.overdueCount;
    return Material(
      color: Colors.red.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.schedule_outlined, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1
                    ? '1 loan is past its due date'
                    : '$count loans are past their due date',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

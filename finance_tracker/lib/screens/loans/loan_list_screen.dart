import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/loans/loan_list_view.dart';
import '../../widgets/loans/loan_person_summary_view.dart';
import '../../widgets/loans/record_payment_sheet.dart';
import 'loan_form_screen.dart';
import '../../widgets/motion/full_motion_route.dart';

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
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();

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

  Future<void> _openForm() async {
    await Navigator.of(context).push(
      FullMotionPageRoute(builder: (_) => const LoanFormScreen()),
    );
  }

  /// Recording from the card is the same flow as from the detail screen, so the two cannot
  /// report different outcomes.
  Future<void> _recordPayment(Loan loan) async {
    final outcome = await RecordPaymentSheet.show(context, loan);
    if (outcome == null || !mounted) return;

    await context.read<LoanProvider>().loadLoans();
    if (!mounted) return;

    final message = outcome.alreadyRecorded
        ? 'Already recorded.'
        : outcome.surplusAdded > 0
            ? 'Payment recorded — ${Formatters.currency(outcome.surplusAdded)} over the amount.'
            : outcome.settled
                ? 'Payment recorded — loan settled.'
                : 'Payment recorded.';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        // Secondary sub-tabs: the selected one is a filled pill, not an underline. The
        // indicator and colours come from `tabBarTheme` so the two tabs cannot drift.
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Keeps the pill snug around the label rather than the full bar height.
          indicatorPadding: const EdgeInsets.symmetric(vertical: 8),
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
                LoanListView(
                  onAddLoan: _openForm,
                  onRecordPayment: _recordPayment,
                ),
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

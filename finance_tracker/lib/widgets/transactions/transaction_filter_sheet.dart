import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../models/transaction.dart';

/// Bottom sheet for filtering and sorting transactions.
/// Returns the new [TransactionFilters] when "Apply" is tapped.
class TransactionFilterSheet extends StatefulWidget {
  final TransactionFilters currentFilters;

  const TransactionFilterSheet({required this.currentFilters, super.key});

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late String? _type;
  late int? _source;
  late String? _search;
  late String _sort;
  late String _order;

  @override
  void initState() {
    super.initState();
    final f = widget.currentFilters;
    _type = f.type;
    _source = f.source;
    _search = f.search;
    _sort = f.sort;
    _order = f.order;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Type filter
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
            ],
            selected: {_type},
            onSelectionChanged: (set) => setState(() => _type = set.first),
          ),
          const SizedBox(height: 16),

          // Source filter
          const Text('Source', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: _source,
            decoration: const InputDecoration(
              hintText: 'All sources',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All sources')),
              ...Constants.sources.map(
                (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
              ),
            ],
            onChanged: (v) => setState(() => _source = v),
          ),
          const SizedBox(height: 16),

          // Search
          const Text('Search', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: _search),
            decoration: const InputDecoration(
              hintText: 'Search merchant or description',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            onChanged: (v) => _search = v.trim().isEmpty ? null : v.trim(),
          ),
          const SizedBox(height: 16),

          // Sort
          const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sort,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'date', child: Text('Date')),
                    DropdownMenuItem(value: 'amount', child: Text('Amount')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'date'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _order,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'desc', child: Text('Descending')),
                    DropdownMenuItem(value: 'asc', child: Text('Ascending')),
                  ],
                  onChanged: (v) => setState(() => _order = v ?? 'desc'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, TransactionFilters()),
                child: const Text('Clear All'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  widget.currentFilters.copyWith(
                    type: _type,
                    source: _source,
                    search: _search,
                    sort: _sort,
                    order: _order,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/loan.dart';

/// Bottom sheet for searching, filtering and sorting loans.
/// Returns the new [LoanFilters] when "Apply" is tapped.
class LoanFilterSheet extends StatefulWidget {
  final LoanFilters currentFilters;

  const LoanFilterSheet({required this.currentFilters, super.key});

  @override
  State<LoanFilterSheet> createState() => _LoanFilterSheetState();
}

class _LoanFilterSheetState extends State<LoanFilterSheet> {
  late TextEditingController _searchController;
  late String? _state;
  late String _sort;
  late String _order;

  @override
  void initState() {
    super.initState();
    final f = widget.currentFilters;
    _searchController = TextEditingController(text: f.search ?? '');
    _state = f.state;
    _sort = f.sort;
    _order = f.order;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
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

            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Person',
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String?>(
              initialValue: _state,
              decoration: const InputDecoration(labelText: 'Status', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('Any')),
                DropdownMenuItem(value: LoanState.open, child: Text('Open')),
                DropdownMenuItem(value: LoanState.settled, child: Text('Settled')),
              ],
              onChanged: (v) => setState(() => _state = v),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _sort,
              decoration: const InputDecoration(labelText: 'Sort by', isDense: true),
              items: const [
                DropdownMenuItem(value: 'due_date', child: Text('Due date')),
                DropdownMenuItem(value: 'outstanding', child: Text('Outstanding')),
                DropdownMenuItem(value: 'created_at', child: Text('Recently added')),
              ],
              onChanged: (v) => setState(() => _sort = v ?? 'due_date'),
            ),
            const SizedBox(height: 16),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'asc', label: Text('Ascending')),
                ButtonSegment(value: 'desc', label: Text('Descending')),
              ],
              selected: {_order},
              onSelectionChanged: (set) => setState(() => _order = set.first),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(
                      LoanFilters(direction: widget.currentFilters.direction),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      LoanFilters(
                        // The direction filter lives on the list screen, so keep it.
                        direction: widget.currentFilters.direction,
                        state: _state,
                        search: _searchController.text.trim().isEmpty
                            ? null
                            : _searchController.text.trim(),
                        sort: _sort,
                        order: _order,
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

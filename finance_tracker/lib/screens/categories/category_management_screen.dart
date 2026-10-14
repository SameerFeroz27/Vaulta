import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../providers/category_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';
import 'category_form_screen.dart';
import '../../widgets/motion/full_motion_route.dart';

/// Lists all categories (global + user-created) with the ability to
/// create, edit, and delete user-created categories.
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  @override
  void initState() {
    super.initState();
    // Always force-refresh so newly created categories appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          FullMotionPageRoute(builder: (_) => const CategoryFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.categories.isEmpty) {
            return const LoadingIndicator();
          }
          if (provider.error != null && provider.categories.isEmpty) {
            return ErrorState(
              message: provider.error!,
              onRetry: () => provider.loadCategories(force: true),
            );
          }
          if (provider.categories.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              subtitle: 'Tap the + button to create one.',
            );
          }

          final userCategories = provider.categories
              .where((c) => !c.isGlobal)
              .toList();
          final globalCategories = provider.categories
              .where((c) => c.isGlobal)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              if (userCategories.isNotEmpty) ...[
                const _SectionLabel(label: 'Your Categories'),
                ...userCategories.map(
                  (c) => _CategoryTile(
                    category: c,
                    onTap: () => Navigator.push(
                      context,
                      FullMotionPageRoute(
                        builder: (_) => CategoryFormScreen(category: c),
                      ),
                    ),
                  ),
                ),
              ],
              if (globalCategories.isNotEmpty) ...[
                const _SectionLabel(label: 'Default Categories'),
                ...globalCategories.map((c) => _CategoryTile(category: c)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback? onTap;

  const _CategoryTile({required this.category, this.onTap});

  String get _typeLabel {
    return switch (category.transactionType) {
      'expense' => 'Expense',
      'income' => 'Income',
      'both' => 'Both',
      _ => category.transactionType,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: category.colorValue.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(category.icon, style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Text(category.name),
        subtitle: Text(
          _typeLabel,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        trailing: category.isGlobal
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

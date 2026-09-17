import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../providers/category_provider.dart';
import '../../widgets/common/confirm_dialog.dart';

/// Form for creating or editing a category.
///
/// Pass a [category] to edit an existing user-created category;
/// omit it to create a new one.
class CategoryFormScreen extends StatefulWidget {
  final Category? category;

  const CategoryFormScreen({super.key, this.category});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late String _transactionType;
  late Color _selectedColor;
  bool _isSaving = false;

  bool get _isEditing => widget.category != null;

  static const List<String> _presetEmojis = [
    '🍽️',
    '🛒',
    '🚗',
    '🏠',
    '💡',
    '🎬',
    '✈️',
    '🏥',
    '📚',
    '👕',
    '🎁',
    '💰',
    '💵',
    '💳',
    '📱',
    '💻',
    '🏋️',
    '🍺',
    '☕',
    '🐾',
    '🔧',
    '🧾',
    '📈',
    '🏦',
  ];

  static const List<Color> _presetColors = [
    Color(0xFFE53935),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF1976D2),
    Color(0xFF03A9F4),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF43A047),
    Color(0xFF8BC34A),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFF795548),
    Color(0xFF607D8B),
    Color(0xFFBDC3C7),
  ];

  @override
  void initState() {
    super.initState();
    final cat = widget.category;
    _nameController = TextEditingController(text: cat?.name ?? '');
    _iconController = TextEditingController(text: cat?.icon ?? '📁');
    _transactionType = cat?.transactionType ?? 'expense';
    _selectedColor = cat?.colorValue ?? const Color(0xFFBDC3C7);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final provider = context.read<CategoryProvider>();
    final name = _nameController.text.trim();
    final icon = _iconController.text.trim().isEmpty
        ? '📁'
        : _iconController.text.trim();
    final color = _colorToHex(_selectedColor);

    try {
      if (_isEditing) {
        await provider.updateCategory(
          id: widget.category!.id,
          name: name,
          icon: icon,
          color: color,
          transactionType: _transactionType,
        );
      } else {
        await provider.createCategory(
          name: name,
          icon: icon,
          color: color,
          transactionType: _transactionType,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final provider = context.read<CategoryProvider>();
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete category?',
      message:
          'Transactions using this category will lose their category label. '
          'This cannot be undone.',
    );
    if (!confirmed) return;

    setState(() => _isSaving = true);

    try {
      await provider.deleteCategory(widget.category!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _extractErrorMessage(Object error) {
    final str = error.toString();
    if (str.contains('CONFLICT')) {
      return 'A category with this name already exists.';
    }
    if (str.contains('FORBIDDEN')) {
      return 'You can only edit your own custom categories.';
    }
    return str.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Category' : 'New Category'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Groceries',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                if (value.trim().length > 50) {
                  return 'Name cannot exceed 50 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Transaction type
            Text(
              'Type',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
                ButtonSegment(value: 'both', label: Text('Both')),
              ],
              selected: {_transactionType},
              onSelectionChanged: (set) {
                setState(() => _transactionType = set.first);
              },
            ),
            const SizedBox(height: 20),

            // Icon
            Text(
              'Icon',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetEmojis.map((emoji) {
                final isSelected = _iconController.text == emoji;
                return GestureDetector(
                  onTap: () => setState(() => _iconController.text = emoji),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _iconController,
              decoration: const InputDecoration(
                labelText: 'Custom icon',
                hintText: 'Type or paste an emoji',
              ),
              textAlign: TextAlign.center,
              maxLength: 10,
            ),
            const SizedBox(height: 20),

            // Color
            Text(
              'Color',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetColors.map((color) {
                final isSelected =
                    _selectedColor.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : Border.all(color: Colors.transparent, width: 3),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Save
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEditing ? 'Update' : 'Create'),
            ),

            // Delete (edit mode only)
            if (_isEditing) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSaving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                child: const Text('Delete Category'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

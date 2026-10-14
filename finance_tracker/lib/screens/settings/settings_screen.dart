import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_client.dart';
import '../budgets/budget_list_screen.dart';
import '../categories/category_management_screen.dart';
import '../receipts/receipt_list_screen.dart';
import '../../widgets/motion/full_motion_route.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // Profile header
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    (user?.name ?? '?')[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user?.name ?? 'User',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Account section
          const _SectionHeader(title: 'Account'),
          Card(
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.attach_money_outlined,
                  label: 'Base Currency',
                  subtitle: 'Dashboard totals convert to this currency',
                  value:
                      '${Constants.currencySymbol(user?.currency ?? 'PKR')} ${user?.currency ?? 'PKR'}',
                  onTap: () => _showCurrencyPicker(context, auth),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.currency_exchange_outlined,
                  label: 'Exchange Rates',
                  subtitle: 'Auto-fetched from live API',
                  value: (user?.exchangeRates?.isNotEmpty ?? false)
                      ? '${user!.exchangeRates!.length} live rates'
                      : 'Tap to fetch',
                  onTap: () => _showExchangeRatesDialog(context, auth),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.schedule_outlined,
                  label: 'Timezone',
                  value: user?.timezone ?? 'Asia/Karachi',
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.lock_outline,
                  label: 'Change Password',
                  value: 'Change',
                  onTap: () => _showChangePasswordDialog(context, auth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // App section
          const _SectionHeader(title: 'App'),
          Card(
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.category_outlined,
                  label: 'Categories',
                  value: 'Manage',
                  onTap: () => Navigator.push(
                    context,
                    FullMotionPageRoute(
                      builder: (_) => const CategoryManagementScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Budgets',
                  value: 'Manage',
                  onTap: () => Navigator.push(
                    context,
                    FullMotionPageRoute(builder: (_) => const BudgetListScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.receipt_outlined,
                  label: 'Scan History',
                  value: 'View',
                  onTap: () => Navigator.push(
                    context,
                    FullMotionPageRoute(
                      builder: (_) => const ReceiptListScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Appearance section
          const _SectionHeader(title: 'Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Auto'),
                  icon: Icon(Icons.settings_outlined),
                ),
              ],
              selected: {context.watch<ThemeProvider>().themeMode},
              onSelectionChanged: (set) =>
                  context.read<ThemeProvider>().setThemeMode(set.first),
            ),
          ),
          const SizedBox(height: 16),

          // Network section
          const _SectionHeader(title: 'Network'),
          Card(
            child: _SettingTile(
              icon: Icons.dns_outlined,
              label: 'Backend URL',
              value: Constants.hasCustomApiBaseUrl
                  ? Constants.apiBaseUrl
                  : 'Default',
              onTap: () => _showNetworkConfigDialog(context),
            ),
          ),
          const SizedBox(height: 16),

          // About section
          const _SectionHeader(title: 'About'),
          Card(
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.info_outline,
                  label: 'Version',
                  value: '1.0.0',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Log out sits behind its own divider, in the danger colour, with room beneath it
          // so the row scrolls fully clear of the nav bar instead of ending flush against it.
          const Divider(height: 1),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: AppTheme.expenseFor(context)),
              title: Text(
                'Log out',
                style: TextStyle(
                  color: AppTheme.expenseFor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _confirmLogout(context, auth),
            ),
          ),
          SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom),
        ],
      ),
    );
  }

  void _showNetworkConfigDialog(BuildContext context) {
    final controller = TextEditingController(text: Constants.apiBaseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            hintText: 'http://192.168.1.50:5000/api',
            helperText: "Use your computer's LAN IP for real devices",
          ),
        ),
        actions: [
          if (Constants.hasCustomApiBaseUrl)
            TextButton(
              onPressed: () async {
                final apiClient = context.read<ApiClient>();
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await apiClient.resetApiBaseUrl();
                  if (!ctx.mounted) return;
                  navigator.pop();
                  if (mounted) setState(() {});
                } catch (e) {
                  if (ctx.mounted) navigator.pop();
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to reset URL: $e')),
                    );
                  }
                }
              },
              child: const Text('Reset to Default'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty || Uri.tryParse(url) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid URL')),
                );
                return;
              }
              final apiClient = context.read<ApiClient>();
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await apiClient.saveApiBaseUrl(url);
                if (!ctx.mounted) return;
                navigator.pop();
                if (mounted) setState(() {});
              } catch (e) {
                if (ctx.mounted) navigator.pop();
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to save URL: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showCurrencyPicker(BuildContext context, AuthProvider auth) {
    final current = auth.user?.currency ?? 'PKR';

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Base Currency'),
        children: Constants.supportedCurrencies.map((c) {
          return ListTile(
            leading: c.code == current
                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                : const SizedBox(width: 24),
            title: Text('${c.symbol}  ${c.code}'),
            subtitle: Text(c.name),
            onTap: () {
              Navigator.pop(ctx);
              if (c.code == current) return;
              // Change currency, clear the old rates, then auto-fetch new ones.
              auth
                  .updateProfile(currency: c.code, clearExchangeRates: true)
                  .then((_) => auth.refreshExchangeRates())
                  .then((_) {
                if (!context.mounted) return;
                // Dashboard totals and budget spend are both expressed in the base
                // currency, so re-fetch them here rather than leaving the old figures
                // sitting under the new symbol until the next tab visit.
                context.read<DashboardProvider>().loadDashboard();
                context.read<BudgetProvider>().loadBudgets(force: true);
              });
            },
          );
        }).toList(),
      ),
    );
  }

  void _showExchangeRatesDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => _ExchangeRatesDialog(auth: auth),
    );
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.expenseFor(context),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(auth: auth),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
    );
    final valueStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 14,
    );

    final tile = ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle!, style: subtitleStyle) : null,
      trailing: Flexible(
        child: Text(
          value,
          style: valueStyle,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );

    if (onTap != null) {
      return ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label),
        subtitle: subtitle != null ? Text(subtitle!, style: subtitleStyle) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: valueStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
        onTap: onTap,
      );
    }

    return tile;
  }
}

/// Dialog showing auto-fetched exchange rates with a Refresh button.
/// Rates are fetched from a live API — no manual entry needed.
class _ExchangeRatesDialog extends StatefulWidget {
  final AuthProvider auth;

  const _ExchangeRatesDialog({required this.auth});

  @override
  State<_ExchangeRatesDialog> createState() => _ExchangeRatesDialogState();
}

class _ExchangeRatesDialogState extends State<_ExchangeRatesDialog> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await widget.auth.refreshExchangeRates();
    if (!mounted) return;
    setState(() => _refreshing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.auth.error != null
              ? widget.auth.error!
              : 'Exchange rates updated',
        ),
        backgroundColor: widget.auth.error != null
            ? Colors.red.shade700
            : Colors.green,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Auto-fetch if no rates are set
    if (widget.auth.user?.exchangeRates?.isEmpty ?? true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseCurrency = widget.auth.user?.currency ?? 'PKR';
    final rates = widget.auth.user?.exchangeRates ?? <String, double>{};
    final otherCurrencies = Constants.supportedCurrencies
        .where((c) => c.code != baseCurrency)
        .toList();

    return AlertDialog(
      title: Text('Exchange Rates (1 X = ? $baseCurrency)'),
      content: SizedBox(
        width: double.maxFinite,
        child: _refreshing
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Rates are fetched automatically from a live API. '
                    'Dashboard totals convert all transactions to $baseCurrency.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...otherCurrencies.map((c) {
                    final rate = rates[c.code];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${c.symbol}  ${c.code}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            rate != null
                                ? '1 ${c.code} = ${rate.toStringAsFixed(2)} $baseCurrency'
                                : '—',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: _refreshing ? null : _refresh,
          child: _refreshing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Refresh'),
        ),
      ],
    );
  }
}

/// Dialog for changing the user's password.
/// StatefulWidget for proper lifecycle management of controllers and
/// the saving state — avoids setState-after-dispose assertions.
class _ChangePasswordDialog extends StatefulWidget {
  final AuthProvider auth;

  const _ChangePasswordDialog({required this.auth});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await widget.auth.changePassword(
      _currentController.text,
      _newController.text,
    );

    if (!mounted) return;

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Password changed successfully'
              : (widget.auth.error ?? 'Failed to change password'),
        ),
        backgroundColor: success ? Colors.green : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentController,
              decoration: const InputDecoration(
                labelText: 'Current Password',
              ),
              obscureText: _obscure,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newController,
              decoration: const InputDecoration(
                labelText: 'New Password',
              ),
              obscureText: _obscure,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Required';
                }
                if (value.length < 8) {
                  return 'Min 8 characters';
                }
                if (value == _currentController.text) {
                  return "You're using the same password. For better security, consider choosing a different one";
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
              ),
              obscureText: _obscure,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Required';
                }
                if (value != _newController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                child: Text(_obscure ? 'Show' : 'Hide'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _change,
          child: const Text('Change'),
        ),
      ],
    );
  }
}

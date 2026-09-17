import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_client.dart';
import '../budgets/budget_list_screen.dart';
import '../categories/category_management_screen.dart';
import '../receipts/receipt_list_screen.dart';

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
                  label: 'Currency',
                  value:
                      '${Constants.currencySymbol(user?.currency ?? 'PKR')} ${user?.currency ?? 'PKR'}',
                  onTap: () => _showCurrencyPicker(context, auth),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.schedule_outlined,
                  label: 'Timezone',
                  value: user?.timezone ?? 'Asia/Karachi',
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
                    MaterialPageRoute(
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
                    MaterialPageRoute(builder: (_) => const BudgetListScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.receipt_outlined,
                  label: 'Scan History',
                  value: 'View',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
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
                  label: Text('System'),
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

          // Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () => _confirmLogout(context, auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              child: const Text('Logout'),
            ),
          ),
          const SizedBox(height: 32),
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
          autofocus: true,
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
                  if (mounted) setState(() {});
                  navigator.pop();
                } catch (e) {
                  navigator.pop();
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
                if (mounted) setState(() {});
                navigator.pop();
              } catch (e) {
                navigator.pop();
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
        title: const Text('Select Currency'),
        children: Constants.supportedCurrencies.map((c) {
          return ListTile(
            leading: c.code == current
                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                : const SizedBox(width: 24),
            title: Text('${c.symbol}  ${c.code}'),
            subtitle: Text(c.name),
            onTap: () {
              Navigator.pop(ctx);
              if (c.code != current) {
                auth.updateProfile(currency: c.code);
              }
            },
          );
        }).toList(),
      ),
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
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
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
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (onTap != null) {
      return ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
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

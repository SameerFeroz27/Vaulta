import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Ticked by default, which keeps today's behaviour: the session survives a restart.
  /// Unticked keeps the tokens in memory only, so closing the app signs the user out.
  bool _keepSignedIn = true;

  /// The submit-level failure, shown inline as a banner. Field-level failures come from
  /// the validators.
  String? _error;
  int _shakeTrigger = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Drop the keyboard first, so the spinner and any errors are readable rather than
    // hidden behind it.
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _error = 'Check the highlighted fields and try again.';
        _shakeTrigger++;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
      keepSignedIn: _keepSignedIn,
    );

    if (!success && mounted) {
      setState(() {
        _error = auth.error ?? 'Login failed';
        _shakeTrigger++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthLayout(
      tagline: 'Sign in to manage your finances',
      footer:
          'Vaulta never stores a full card number or your bank login — only the last four digits.',
      child: Shake(
        trigger: _shakeTrigger,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                // An email is never capitalised and never spell-checked.
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _error!),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: AuthTextButton(
                  label: 'Forgot password?',
                  onPressed:
                      auth.isLoading ? null : () => context.go('/forgot-password'),
                ),
              ),
              const SizedBox(height: 2),
              AuthSubmitButton(
                label: 'Sign in',
                busy: auth.isLoading,
                onPressed: _handleLogin,
              ),
              const SizedBox(height: 2),
              AuthTextButton(
                label: "Don't have an account? Create one",
                onPressed: auth.isLoading ? null : () => context.go('/register'),
              ),
              const SizedBox(height: 2),
              _KeepSignedIn(
                value: _keepSignedIn,
                onChanged: (value) => setState(() => _keepSignedIn = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Keep me signed in" — a 44 px target, and one action for both the box and its label.
class _KeepSignedIn extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _KeepSignedIn({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (checked) => onChanged(checked ?? false),
            ),
            const SizedBox(width: 4),
            Text(
              'Keep me signed in',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_layout.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _error;
  int _shakeTrigger = 0;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestReset() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _error = 'Check the highlighted field and try again.';
        _shakeTrigger++;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.forgotPassword(_emailController.text.trim());

    if (!mounted) return;
    if (success) {
      // The reset screen carries the instruction to enter the code, so a snackbar here
      // would only repeat it over the form.
      context.go('/reset-password');
    } else {
      setState(() {
        _error = auth.error ?? 'Failed to generate reset code';
        _shakeTrigger++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthLayout(
      tagline: "Enter your email and we'll send a 6-digit code",
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
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _handleRequestReset(),
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              AuthSubmitButton(
                label: 'Send reset code',
                busy: auth.isLoading,
                onPressed: _handleRequestReset,
              ),
              const SizedBox(height: 8),
              AuthTextButton(
                label: 'Back to sign in',
                onPressed: auth.isLoading ? null : () => context.go('/login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

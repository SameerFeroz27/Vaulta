import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_layout.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  String? _error;
  int _shakeTrigger = 0;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
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
    final success = await auth.resetPassword(
      _otpController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully. Please log in.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/login');
    } else {
      setState(() {
        _error = auth.error ?? 'Failed to reset password';
        _shakeTrigger++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthLayout(
      tagline: 'Enter the 6-digit code sent to your email',
      child: Shake(
        trigger: _shakeTrigger,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _otpController,
                decoration: const InputDecoration(
                  labelText: '6-Digit Code',
                  hintText: 'Enter the code from your email',
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the 6-digit code';
                  }
                  if (value.trim().length != 6) {
                    return 'Code must be 6 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'New Password',
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
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleResetPassword(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
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
                label: 'Reset password',
                busy: auth.isLoading,
                onPressed: _handleResetPassword,
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

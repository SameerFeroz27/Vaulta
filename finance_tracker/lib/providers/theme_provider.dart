import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/constants.dart';

/// Manages the app's theme mode (light, dark, or system) and persists
/// the user's choice to secure storage.
class ThemeProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  /// Load the saved theme preference from storage. Defaults to
  /// [ThemeMode.system] if no preference is stored.
  Future<void> init() async {
    final saved = await _storage.read(key: Constants.themeModeKey);
    if (saved != null) {
      _themeMode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light,
      };
      notifyListeners();
    }
  }

  /// Update the theme mode and persist it to storage.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _storage.write(key: Constants.themeModeKey, value: mode.name);
  }
}

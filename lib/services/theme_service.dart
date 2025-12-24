import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // This is a bit tricky without context, but we can default to false or check platform brightness if possible.
      // For simplicity in this singleton, we'll rely on the UI to check brightness using MediaQuery.
      // But for the map URL, we need a concrete value.
      // Let's just default to light if system, or we can't easily know without context.
      // Better approach: The UI widgets will check Theme.of(context).brightness.
      return false;
    }
    return _themeMode == ThemeMode.dark;
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    // 0: System, 1: Light, 2: Dark
    switch (themeIndex) {
      case 1:
        _themeMode = ThemeMode.light;
        break;
      case 2:
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> updateTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    int index = 0;
    if (mode == ThemeMode.light) index = 1;
    if (mode == ThemeMode.dark) index = 2;
    await prefs.setInt('theme_mode', index);
  }

  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.dark) {
      await updateTheme(ThemeMode.light);
    } else {
      await updateTheme(ThemeMode.dark);
    }
  }
}

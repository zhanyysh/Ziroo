import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'services/theme_service.dart';
import 'router.dart'; // Импортируем наш роутер

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: "https://rmqwopgsvpbybbxrtccc.supabase.co",
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtcXdvcGdzdnBieWJieHJ0Y2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNTI1MzgsImV4cCI6MjA3OTcyODUzOH0.znJr6DQp-hD3kHf9gloEuORvS2b3Kv71Jpk64AwbLHk',
  );

  final themeService = ThemeService();
  await themeService.loadTheme();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        return MaterialApp.router(
          // Используем router конструктор
          routerConfig: router, // Подключаем наш конфиг
          title: 'Learn Flutter and Supabase',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeService().themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
              surface: const Color(0xFF121212), // Dark background
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              backgroundColor: Color(0xFF1E1E1E),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF1E1E1E),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E1E1E),
              selectedItemColor: Colors.deepPurpleAccent,
              unselectedItemColor: Colors.grey,
            ),
          ),
        );
      },
    );
  }
}

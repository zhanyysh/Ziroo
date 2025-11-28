import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'widgets/auth_wrapper.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url : "https://rmqwopgsvpbybbxrtccc.supabase.co",
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtcXdvcGdzdnBieWJieHJ0Y2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNTI1MzgsImV4cCI6MjA3OTcyODUzOH0.znJr6DQp-hD3kHf9gloEuORvS2b3Kv71Jpk64AwbLHk'
  );
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learn Flutter and Supabase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthWrapper(),
    );
  }
}
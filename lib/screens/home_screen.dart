// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser!;
    final response = await Supabase.instance.client
        .from('profiles')
        .select('email, role')
        .eq('id', user.id)
        .single();

    setState(() {
      profile = response;
      isLoading = false;
    });
  }

  bool get isAdmin => profile?['role'] == 'admin';

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: isLoading
       ? const Center(child: CircularProgressIndicator())
       : Center (
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Hello ${profile?['email'] ?? user.email ?? 'Not set'}!', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 10),
            Text('Role: ${profile?['role'] ?? 'user'}'),
            const SizedBox(height: 30),
            if (isAdmin)
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard())),
                child: const Text('Admin Panel'),
              )
          ],
        ),
      ),
    );
  }
}
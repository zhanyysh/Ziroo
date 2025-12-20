import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin/admin_dashboard.dart';
import 'user_screen.dart';

class RoleCheckScreen extends StatefulWidget {
  const RoleCheckScreen({super.key});

  @override
  State<RoleCheckScreen> createState() => _RoleCheckScreenState();
}

class _RoleCheckScreenState extends State<RoleCheckScreen> {
  bool _loading = true;
  String _role = 'user';

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // Should not happen if AuthWrapper works correctly
        return;
      }

      final data =
          await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .single();

      if (mounted) {
        setState(() {
          _role = data['role'] ?? 'user';
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback to user if error (or handle error appropriately)
      if (mounted) {
        setState(() {
          _role = 'user';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_role == 'admin') {
      return const AdminDashboard();
    } else {
      return const UserScreen();
    }
  }
}

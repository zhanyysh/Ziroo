// lib/screens/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();
  bool loading = true;

  final roles = ['user', 'manager', 'admin'];

  @override
  void initState() {
    super.initState();
    _setupRealtime();
    _searchController.addListener(_filterUsers);
  }

  void _setupRealtime() {
    _channel = Supabase.instance.client
        .channel('public:profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            print('Realtime update detected: ${payload.newRecord}');  // For debugging
            loadUsers(); // Любое изменение → мгновенное обновление
          },
        )
        .subscribe((status, error) {
          // Debug: Print status to console
          print('Realtime status: $status');
          if (error != null) {
            print('Realtime error: $error');
          }
        });

    loadUsers(); // Первая загрузка
  }

  Future<void> loadUsers() async {
    setState(() => loading = true);
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, email, full_name, role, created_at');

      final List<Map<String, dynamic>> data =
          List<Map<String, dynamic>>.from(response);

      setState(() {
        users = data;
        filteredUsers = data;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredUsers = users.where((user) {
        final email = (user['email'] ?? '').toString().toLowerCase();
        final name = (user['full_name'] ?? '').toString().toLowerCase();
        return email.contains(query) || name.contains(query);
      }).toList();
    });
  }

  Future<void> updateRole(String userId, String newRole) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'role': newRole})
        .eq('id', userId);
    // Realtime сам обновит список — ничего больше не нужно!
  }

  Future<void> deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) throw Exception('Not logged in');

        // Call your Edge Function (replace with your project ref)
        final response = await http.post(
          Uri.parse('https://rmqwopgsvpbybbxrtccc.supabase.co/functions/v1/delete-user?userId=$userId'),
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully!')),
          );
          // Realtime will auto-remove from list
        } else {
          throw Exception('Server error: ${response.body}');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadUsers),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by email or name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : filteredUsers.isEmpty
                    ? const Center(child: Text('No users found'))
                    : ListView.builder(
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, i) {
                          final user = filteredUsers[i];
                          final String role = user['role'] ?? 'user';

                          return Dismissible(
                            key: Key(user['id']),
                            direction: DismissDirection.endToStart,
                            background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                            onDismissed: (_) => deleteUser(user['id']),
                            child: Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.deepPurple,
                                  child: Text(
                                    (user['email'] as String? ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(user['email'] ?? 'No email'),
                                subtitle: Text(user['full_name'] ?? 'No name'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    DropdownButton<String>(
                                      value: role,
                                      items: roles
                                          .map((r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(r.toUpperCase(),
                                                    style: TextStyle(
                                                      color: r == 'admin'
                                                          ? Colors.green
                                                          : r == 'moderator'
                                                              ? Colors.orange
                                                              : Colors.grey[700],
                                                      fontWeight: FontWeight.bold,
                                                    )),
                                              ))
                                          .toList(),
                                      onChanged: (val) => val != null ? updateRole(user['id'], val) : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => deleteUser(user['id']),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
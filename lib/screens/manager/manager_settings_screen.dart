import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../services/theme_service.dart';

class ManagerSettingsScreen extends StatefulWidget {
  const ManagerSettingsScreen({super.key});

  @override
  State<ManagerSettingsScreen> createState() => _ManagerSettingsScreenState();
}

class _ManagerSettingsScreenState extends State<ManagerSettingsScreen> {
  String? _fullName;
  String? _email;
  List<Map<String, dynamic>> _allBranches = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Get profile
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      // Get all branches через RPC
      final branchesData = await Supabase.instance.client
          .rpc('get_manager_branches', params: {'p_manager_id': user.id});
      
      List<Map<String, dynamic>> branches = [];
      
      if (branchesData != null && (branchesData as List).isNotEmpty) {
        branches = List<Map<String, dynamic>>.from(branchesData);
      } else {
        // Fallback на старый способ
        final fallbackData = await Supabase.instance.client
            .from('company_branches')
            .select('*, companies(*)')
            .eq('manager_id', user.id);
        
        if (fallbackData != null) {
          branches = List<Map<String, dynamic>>.from(fallbackData);
        }
      }

      if (mounted) {
        setState(() {
          _fullName = profile?['full_name'];
          _email = user.email;
          _allBranches = branches;
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = ThemeService();
    final name = _fullName ?? 'Менеджер';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_email != null)
                          Text(
                            _email!,
                            style: theme.textTheme.bodySmall,
                          ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Менеджер',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Branch info - показываем все филиалы
          if (_allBranches.isNotEmpty) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          _allBranches.length == 1 ? 'Мой филиал' : 'Мои филиалы (${_allBranches.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ..._allBranches.map((branch) {
                      final company = branch['companies'] as Map<String, dynamic>?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            // Logo
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: company?['logo_url'] != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        company!['logo_url'],
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.store,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    )
                                  : Icon(Icons.store, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    company?['name'] ?? 'Компания',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    branch['name'] ?? 'Филиал',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '-${company?['discount_percentage'] ?? 0}%',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Вам ещё не назначен филиал. Обратитесь к администратору.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Theme toggle
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListenableBuilder(
              listenable: themeService,
              builder: (context, _) {
                return SwitchListTile(
                  title: const Text('Тёмная тема'),
                  subtitle: const Text('Переключить оформление'),
                  secondary: Icon(
                    themeService.themeMode == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  value: themeService.themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    themeService.updateTheme(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Sign out button
          FilledButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

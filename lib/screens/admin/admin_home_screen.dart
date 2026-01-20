import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  
  int _totalUsers = 0;
  int _totalCompanies = 0;
  int _totalBranches = 0;
  int _totalTransactions = 0;
  double _totalRevenue = 0;
  String? _adminName;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    
    try {
      // Get admin profile
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final profile = await _supabase
            .from('profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        _adminName = profile?['full_name'];
      }

      // Get counts
      final users = await _supabase.from('profiles').select('id');
      final companies = await _supabase.from('companies').select('id');
      final branches = await _supabase.from('company_branches').select('id');
      
      // Try to get transactions
      try {
        final transactions = await _supabase.from('transactions').select('final_amount');
        _totalTransactions = transactions.length;
        _totalRevenue = 0;
        for (final t in transactions) {
          _totalRevenue += (t['final_amount'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        _totalTransactions = 0;
        _totalRevenue = 0;
      }

      if (mounted) {
        setState(() {
          _totalUsers = users.length;
          _totalCompanies = companies.length;
          _totalBranches = branches.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = _getGreeting();
    
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: CustomScrollView(
                slivers: [
                  // Custom App Bar
                  SliverAppBar(
                    expandedHeight: 140,
                    floating: false,
                    pinned: true,
                    elevation: 0,
                    backgroundColor: theme.colorScheme.primary,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.primary.withOpacity(0.8),
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  greeting,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _adminName ?? 'Администратор',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _loadStats,
                      ),
                    ],
                  ),
                  
                  // Stats Cards
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Обзор',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Stats Grid
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  theme,
                                  icon: Icons.people,
                                  color: Colors.blue,
                                  value: _totalUsers.toString(),
                                  label: 'Пользователей',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  theme,
                                  icon: Icons.store,
                                  color: Colors.orange,
                                  value: _totalCompanies.toString(),
                                  label: 'Компаний',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  theme,
                                  icon: Icons.location_on,
                                  color: Colors.green,
                                  value: _totalBranches.toString(),
                                  label: 'Филиалов',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  theme,
                                  icon: Icons.receipt_long,
                                  color: Colors.purple,
                                  value: _totalTransactions.toString(),
                                  label: 'Транзакций',
                                ),
                              ),
                            ],
                          ),
                          
                          // Revenue Card
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade400,
                                  Colors.green.shade600,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Общая выручка',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_totalRevenue.toStringAsFixed(0)} ₽',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Quick Actions
                          const SizedBox(height: 24),
                          Text(
                            'Быстрые действия',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  
                  // Action Cards Grid
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.1,
                      ),
                      delegate: SliverChildListDelegate([
                        _buildActionCard(
                          context,
                          theme,
                          icon: Icons.people,
                          color: Colors.blue,
                          title: 'Пользователи',
                          subtitle: 'Управление',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UsersScreen()),
                          ),
                        ),
                        _buildActionCard(
                          context,
                          theme,
                          icon: Icons.bar_chart,
                          color: Colors.orange,
                          title: 'Статистика',
                          subtitle: 'Аналитика',
                          onTap: () {},
                        ),
                        _buildActionCard(
                          context,
                          theme,
                          icon: Icons.campaign,
                          color: Colors.red,
                          title: 'Акции',
                          subtitle: 'Промо',
                          onTap: () {},
                        ),
                        _buildActionCard(
                          context,
                          theme,
                          icon: Icons.support_agent,
                          color: Colors.teal,
                          title: 'Поддержка',
                          subtitle: 'Обращения',
                          onTap: () {},
                        ),
                      ]),
                    ),
                  ),
                  
                  const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
                ],
              ),
            ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Доброе утро,';
    if (hour < 17) return 'Добрый день,';
    return 'Добрый вечер,';
  }

  Widget _buildStatCard(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

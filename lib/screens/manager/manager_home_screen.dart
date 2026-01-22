import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _allBranches = []; // Все филиалы менеджера
  Map<String, dynamic>? _branch;
  Map<String, dynamic>? _company;
  int _selectedBranchIndex = 0;
  
  // Today's statistics
  int _todayTransactions = 0;
  double _todayTotal = 0;
  double _todayDiscounts = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Получаем ВСЕ филиалы менеджера (через новую таблицу branch_managers)
      final branchesData = await _supabase
          .rpc('get_manager_branches', params: {'p_manager_id': userId});
      
      List<Map<String, dynamic>> branches = [];
      
      if (branchesData != null && (branchesData as List).isNotEmpty) {
        branches = List<Map<String, dynamic>>.from(branchesData);
      } else {
        // Fallback на старый способ если RPC не вернул данные
        final fallbackData = await _supabase
            .from('company_branches')
            .select('*, companies(*)')
            .eq('manager_id', userId);
        
        if (fallbackData != null) {
          branches = List<Map<String, dynamic>>.from(fallbackData);
        }
      }

      _allBranches = branches;

      if (branches.isNotEmpty) {
        await _selectBranch(_selectedBranchIndex.clamp(0, branches.length - 1));
      } else {
        _branch = null;
        _company = null;
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _selectBranch(int index) async {
    if (index < 0 || index >= _allBranches.length) return;
    
    _selectedBranchIndex = index;
    final branchData = _allBranches[index];
    
    _branch = branchData;
    // Обработка companies (может быть JSON из RPC или Map из select)
    final companiesData = branchData['companies'];
    _company = companiesData is Map<String, dynamic> ? companiesData : null;

    // Get today's statistics for selected branch
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    
    try {
      final transactions = await _supabase
          .from('transactions')
          .select()
          .eq('branch_id', branchData['id'])
          .gte('created_at', startOfDay.toIso8601String());

      _todayTransactions = transactions.length;
      _todayTotal = 0;
      _todayDiscounts = 0;
      
      for (final t in transactions) {
        _todayTotal += (t['final_amount'] as num).toDouble();
        _todayDiscounts += (t['discount_amount'] as num).toDouble();
      }
    } catch (e) {
      _todayTransactions = 0;
      _todayTotal = 0;
      _todayDiscounts = 0;
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель менеджера'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _branch == null
              ? _buildNoBranchAssigned()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Branch selector (если несколько филиалов)
                        if (_allBranches.length > 1) ...[
                          _buildBranchSelector(theme),
                          const SizedBox(height: 16),
                        ],
                        
                        // Branch info card
                        _buildBranchCard(theme),
                        const SizedBox(height: 24),
                        
                        // Today's stats
                        Text(
                          'Статистика за сегодня',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Stats grid
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                theme,
                                icon: Icons.receipt_long,
                                color: Colors.blue,
                                title: 'Транзакций',
                                value: _todayTransactions.toString(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                theme,
                                icon: Icons.payments,
                                color: Colors.green,
                                title: 'Выручка',
                                value: '${_todayTotal.toStringAsFixed(0)} ₽',
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
                                icon: Icons.discount,
                                color: Colors.orange,
                                title: 'Скидки',
                                value: '${_todayDiscounts.toStringAsFixed(0)} ₽',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                theme,
                                icon: Icons.percent,
                                color: Colors.purple,
                                title: 'Скидка магазина',
                                value: '${_company?['discount_percentage'] ?? 0}%',
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

  Widget _buildNoBranchAssigned() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_mall_directory_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Филиал не назначен',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Обратитесь к администратору для назначения вас менеджером филиала',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchCard(ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Company logo
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _company?['logo_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _company!['logo_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.store,
                          size: 30,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.store,
                      size: 30,
                      color: theme.colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _company?['name'] ?? 'Магазин',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _branch?['name'] ?? 'Филиал',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_branch?['address'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _branch!['address'],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Discount badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '-${_company?['discount_percentage'] ?? 0}%',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchSelector(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedBranchIndex,
                  isExpanded: true,
                  hint: const Text('Выберите филиал'),
                  items: _allBranches.asMap().entries.map((entry) {
                    final index = entry.key;
                    final branch = entry.value;
                    final company = branch['companies'] as Map<String, dynamic>?;
                    return DropdownMenuItem<int>(
                      value: index,
                      child: Text(
                        '${company?['name'] ?? 'Компания'} - ${branch['name'] ?? 'Филиал'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (index) {
                    if (index != null) {
                      _selectBranch(index);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

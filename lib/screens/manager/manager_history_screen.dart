import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerHistoryScreen extends StatefulWidget {
  const ManagerHistoryScreen({super.key});

  @override
  State<ManagerHistoryScreen> createState() => _ManagerHistoryScreenState();
}

class _ManagerHistoryScreenState extends State<ManagerHistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _allBranches = [];
  bool _loading = true;
  String? _branchId;
  int _selectedBranchIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Получаем все филиалы менеджера через RPC
      final branchesData = await _supabase
          .rpc('get_manager_branches', params: {'p_manager_id': userId});
      
      List<Map<String, dynamic>> branches = [];
      
      if (branchesData != null && (branchesData as List).isNotEmpty) {
        branches = List<Map<String, dynamic>>.from(branchesData);
      } else {
        // Fallback на старый способ
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
        _branchId = branches[0]['id'];
        await _loadTransactions();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectBranch(int index) async {
    if (index < 0 || index >= _allBranches.length) return;
    
    _selectedBranchIndex = index;
    _branchId = _allBranches[index]['id'];
    await _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (_branchId == null) return;
    
    setState(() => _loading = true);
    
    try {
      // Get transactions without join to profiles
      final data = await _supabase
          .from('transactions')
          .select()
          .eq('branch_id', _branchId!)
          .order('created_at', ascending: false)
          .limit(100);

      // Get customer info separately
      final transactions = List<Map<String, dynamic>>.from(data);
      for (var t in transactions) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select('full_name, email, avatar_url')
              .eq('id', t['customer_id'])
              .maybeSingle();
          t['customer_profile'] = profile;
        } catch (e) {
          t['customer_profile'] = null;
        }
      }

      if (mounted) {
        setState(() {
          _transactions = transactions;
          _loading = false;
        });
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

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('История транзакций'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allBranches.isEmpty
              ? _buildNoBranchState()
              : _transactions.isEmpty
                  ? Column(
                      children: [
                        if (_allBranches.length > 1) _buildBranchSelector(theme),
                        Expanded(child: _buildEmptyState()),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTransactions,
                      child: Column(
                        children: [
                          if (_allBranches.length > 1) _buildBranchSelector(theme),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _transactions.length,
                              itemBuilder: (context, index) {
                                final t = _transactions[index];
                                return _buildTransactionCard(t, theme);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildBranchSelector(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.filter_list, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text('Филиал:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedBranchIndex,
                isExpanded: true,
                isDense: true,
                items: _allBranches.asMap().entries.map((entry) {
                  final index = entry.key;
                  final branch = entry.value;
                  final company = branch['companies'] as Map<String, dynamic>?;
                  return DropdownMenuItem<int>(
                    value: index,
                    child: Text(
                      '${company?['name'] ?? ''} - ${branch['name'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (index) {
                  if (index != null) _selectBranch(index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBranchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Филиал не назначен', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'Нет транзакций',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Транзакции появятся после сканирования QR-кодов клиентов',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> t, ThemeData theme) {
    final profile = t['customer_profile'] as Map<String, dynamic>?;
    final customerName = profile?['full_name'] ?? profile?['email'] ?? 'Клиент';
    final avatarUrl = profile?['avatar_url'] as String?;
    final originalAmount = (t['original_amount'] as num).toDouble();
    final discountAmount = (t['discount_amount'] as num).toDouble();
    final finalAmount = (t['final_amount'] as num).toDouble();
    final discountPercent = t['discount_percent'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  radius: 20,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Icon(
                          Icons.person,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatDate(t['created_at']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '-$discountPercent%',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Amounts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAmountColumn('Чек', '${originalAmount.toStringAsFixed(0)} ₽'),
                _buildAmountColumn('Скидка', '-${discountAmount.toStringAsFixed(0)} ₽', 
                    color: Colors.green),
                _buildAmountColumn('Итого', '${finalAmount.toStringAsFixed(0)} ₽',
                    isBold: true, color: theme.colorScheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountColumn(String label, String value, {bool isBold = false, Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

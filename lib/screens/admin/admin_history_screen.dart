import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedAction;

  final List<String> _actionTypes = [
    'Все',
    'create_company',
    'update_company',
    'delete_company',
    'add_branch',
    'delete_branch',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      // Start the query builder
      var query = Supabase.instance.client
          .from('admin_logs')
          .select('*, profiles(email)'); // Returns PostgrestFilterBuilder

      // Apply filters BEFORE ordering
      if (_selectedAction != null && _selectedAction != 'Все') {
        query = query.eq('action_type', _selectedAction!);
      }

      if (_startDate != null) {
        query = query.gte('created_at', _startDate!.toIso8601String());
      }
      if (_endDate != null) {
        // Add one day to include the end date fully
        final end = _endDate!.add(const Duration(days: 1));
        query = query.lt('created_at', end.toIso8601String());
      }

      // Apply ordering LAST
      final data = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // If profiles join fails, try without it
        if (e.toString().contains('profiles')) {
          _loadLogsSimple();
        } else {
          // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          // Fail silently or fallback to simple load if table exists but join fails
          _loadLogsSimple();
        }
      }
    }
  }

  Future<void> _loadLogsSimple() async {
    try {
      var query = Supabase.instance.client.from('admin_logs').select();

      if (_selectedAction != null && _selectedAction != 'Все') {
        query = query.eq('action_type', _selectedAction!);
      }

      if (_startDate != null) {
        query = query.gte('created_at', _startDate!.toIso8601String());
      }
      if (_endDate != null) {
        final end = _endDate!.add(const Duration(days: 1));
        query = query.lt('created_at', end.toIso8601String());
      }

      final data = await query.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange:
          _startDate != null && _endDate != null
              ? DateTimeRange(start: _startDate!, end: _endDate!)
              : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadLogs();
    }
  }

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedAction = null;
    });
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'История действий',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadLogs,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Filters
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Фильтры',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            _startDate == null
                                ? 'Дата'
                                : '${DateFormat('dd.MM').format(_startDate!)} - ${DateFormat('dd.MM').format(_endDate!)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _pickDateRange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outline.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedAction ?? 'Все',
                              isExpanded: true,
                              style: theme.textTheme.bodyMedium,
                              items: _actionTypes
                                  .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          _getActionLabel(e),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() => _selectedAction = val);
                                _loadLogs();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_startDate != null ||
                      (_selectedAction != null && _selectedAction != 'Все'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Сбросить'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Content
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_logs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'История пуста',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final log = _logs[index];
                    return _buildLogCard(log, theme);
                  },
                  childCount: _logs.length,
                ),
              ),
            ),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  String _getActionLabel(String action) {
    switch (action) {
      case 'create_company': return 'Создание';
      case 'update_company': return 'Изменение';
      case 'delete_company': return 'Удаление';
      case 'add_branch': return 'Добавление филиала';
      case 'delete_branch': return 'Удаление филиала';
      default: return action;
    }
  }

  Widget _buildLogCard(Map<String, dynamic> log, ThemeData theme) {
    final date = DateTime.parse(log['created_at']).toLocal();
    final action = log['action_type'] as String;
    final details = log['details'] as String?;
    final profile = log.containsKey('profiles') ? log['profiles'] : null;
    final email = profile != null ? profile['email'] : 'Admin';

    final actionInfo = _getActionInfo(action);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: actionInfo.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              actionInfo.icon,
              color: actionInfo.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details ?? actionInfo.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd.MM.yy HH:mm').format(date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, Color color, String label}) _getActionInfo(String action) {
    switch (action) {
      case 'create_company':
        return (icon: Icons.add_business, color: Colors.green, label: 'Компания создана');
      case 'delete_company':
        return (icon: Icons.delete_outline, color: Colors.red, label: 'Компания удалена');
      case 'update_company':
        return (icon: Icons.edit_outlined, color: Colors.blue, label: 'Компания изменена');
      case 'add_branch':
        return (icon: Icons.add_location, color: Colors.orange, label: 'Филиал добавлен');
      case 'delete_branch':
        return (icon: Icons.location_off, color: Colors.deepOrange, label: 'Филиал удален');
      case 'assign_manager':
        return (icon: Icons.person_add, color: Colors.purple, label: 'Менеджер назначен');
      default:
        return (icon: Icons.history, color: Colors.grey, label: action);
    }
  }
}

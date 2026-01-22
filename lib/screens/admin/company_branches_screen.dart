import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_logger.dart';

class CompanyBranchesScreen extends StatefulWidget {
  final String companyId;
  const CompanyBranchesScreen({super.key, required this.companyId});

  @override
  State<CompanyBranchesScreen> createState() => _CompanyBranchesScreenState();
}

class _CompanyBranchesScreenState extends State<CompanyBranchesScreen> {
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> managers = []; // Available managers
  Map<String, List<Map<String, dynamic>>> branchManagersMap = {}; // branch_id -> list of managers
  bool loading = true;
  final MapController _mapController = MapController();
  LatLng _selectedLocation = const LatLng(42.8746, 74.5698); // Default Bishkek
  final TextEditingController _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadBranches();
    loadManagers();
  }

  Future<void> loadManagers() async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .eq('role', 'manager');

      if (mounted) {
        setState(() {
          managers = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> loadBranchManagers() async {
    try {
      // Загружаем все назначения менеджеров для филиалов этой компании
      final data = await Supabase.instance.client
          .from('branch_managers')
          .select('branch_id, manager_id, profiles!branch_managers_manager_id_fkey(id, full_name, email)')
          .inFilter('branch_id', branches.map((b) => b['id']).toList());

      final Map<String, List<Map<String, dynamic>>> map = {};
      for (var item in data) {
        final branchId = item['branch_id'] as String;
        final profile = item['profiles'] as Map<String, dynamic>?;
        if (profile != null) {
          map.putIfAbsent(branchId, () => []);
          map[branchId]!.add(profile);
        }
      }

      if (mounted) {
        setState(() {
          branchManagersMap = map;
        });
      }
    } catch (e) {
      debugPrint('Error loading branch managers: $e');
      // Fallback: используем старый способ через manager_id
    }
  }

  Future<void> loadBranches() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
          .from('company_branches')
          .select(
            '*, profiles!company_branches_manager_id_fkey(id, full_name, email)',
          )
          .eq('company_id', widget.companyId);
      setState(() {
        branches = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
      // Загружаем менеджеров после загрузки филиалов
      loadBranchManagers();
    } catch (e) {
      // If join fails, try without it
      try {
        final data = await Supabase.instance.client
            .from('company_branches')
            .select()
            .eq('company_id', widget.companyId);
        setState(() {
          branches = List<Map<String, dynamic>>.from(data);
          loading = false;
        });
        loadBranchManagers();
      } catch (e2) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _addBranch() async {
    if (_addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название/адрес филиала')),
      );
      return;
    }

    try {
      await Supabase.instance.client.from('company_branches').insert({
        'company_id': widget.companyId,
        'name': _addressCtrl.text,
        'latitude': _selectedLocation.latitude,
        'longitude': _selectedLocation.longitude,
      });
      _addressCtrl.clear();
      loadBranches();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _showAddDialog() {
    int mapPriority = 3; // Default to Small (3)
    LatLng tempLocation = _selectedLocation;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: EdgeInsets.zero,
                content: SizedBox(
                  width: double.maxFinite,
                  height: 600,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Добавить филиал',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Название / Адрес',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              'Размер на карте:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment<int>(
                                    value: 3,
                                    label: Text('Мелкий'),
                                    icon: Icon(Icons.circle, size: 10),
                                  ),
                                  ButtonSegment<int>(
                                    value: 2,
                                    label: Text('Средний'),
                                    icon: Icon(Icons.store),
                                  ),
                                  ButtonSegment<int>(
                                    value: 1,
                                    label: Text('Крупный'),
                                    icon: Icon(Icons.star),
                                  ),
                                ],
                                selected: {mapPriority},
                                onSelectionChanged: (Set<int> newSelection) {
                                  setState(() {
                                    mapPriority = newSelection.first;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(20),
                          ),
                          child: Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: tempLocation,
                                  initialZoom: 13,
                                  onTap: (tapPosition, point) {
                                    setState(() {
                                      tempLocation = point;
                                      _selectedLocation =
                                          point; // Update parent state too if needed
                                    });
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                            : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                    userAgentPackageName: 'com.example.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: tempLocation,
                                        width:
                                            mapPriority == 1
                                                ? 140
                                                : (mapPriority == 2 ? 50 : 20),
                                        height:
                                            mapPriority == 1
                                                ? 50
                                                : (mapPriority == 2 ? 50 : 20),
                                        child: _buildPreviewMarker(mapPriority),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Positioned(
                                top: 10,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Нажмите на карту для выбора',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A2FF),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _addBranchWithPriority(mapPriority),
                    child: const Text('Добавить'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Widget _buildPreviewMarker(int priority) {
    if (priority == 1) {
      // 1 = Large (Smart Chip)
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.star, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _addressCtrl.text.isEmpty ? "Название" : _addressCtrl.text,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (priority == 2) {
      // 2 = Medium (Floating Pin)
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.store_mall_directory,
              color: Color(0xFF2B2E4A),
              size: 20,
            ),
          ),
          ClipPath(
            clipper: _TriangleClipper(),
            child: Container(width: 10, height: 6, color: Colors.white),
          ),
        ],
      );
    } else {
      // 3 = Small (Soft Dot)
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF4A90E2),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Center(child: SizedBox()),
      );
    }
  }

  Future<void> _addBranchWithPriority(int priority) async {
    if (_addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название/адрес филиала')),
      );
      return;
    }

    try {
      await Supabase.instance.client.from('company_branches').insert({
        'company_id': widget.companyId,
        'name': _addressCtrl.text,
        'latitude': _selectedLocation.latitude,
        'longitude': _selectedLocation.longitude,
        'is_vip': priority == 1, // 1 is now VIP (Large)
        'map_priority': priority,
      });
      await AdminLogger.log(
        'add_branch',
        'Добавлен филиал: ${_addressCtrl.text} (Priority: $priority)',
      );
      _addressCtrl.clear();
      loadBranches();
      Navigator.pop(context);
    } catch (e) {
      // Check for the specific error about missing column
      if (e.toString().contains("Could not find the 'is_vip' column")) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ошибка: В базе данных нет колонки "is_vip". Выполните SQL скрипт.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _deleteBranch(String id) async {
    try {
      await Supabase.instance.client
          .from('company_branches')
          .delete()
          .eq('id', id);

      await AdminLogger.log('delete_branch', 'Удален филиал ID: $id');

      loadBranches();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _assignManager(String branchId, String? managerId) async {
    try {
      if (managerId != null) {
        // Добавляем менеджера в branch_managers
        await Supabase.instance.client.from('branch_managers').upsert({
          'branch_id': branchId,
          'manager_id': managerId,
          'assigned_by': Supabase.instance.client.auth.currentUser?.id,
        }, onConflict: 'branch_id, manager_id');
        
        // Также обновляем legacy поле manager_id (для обратной совместимости)
        await Supabase.instance.client
            .from('company_branches')
            .update({'manager_id': managerId})
            .eq('id', branchId);
      }

      await AdminLogger.log(
        'assign_manager',
        'Добавлен менеджер $managerId для филиала $branchId',
      );

      loadBranches();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Менеджер добавлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _removeManager(String branchId, String managerId) async {
    try {
      await Supabase.instance.client
          .from('branch_managers')
          .delete()
          .eq('branch_id', branchId)
          .eq('manager_id', managerId);

      await AdminLogger.log(
        'remove_manager',
        'Удален менеджер $managerId из филиала $branchId',
      );

      loadBranches();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Менеджер удален'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  void _showManagerDialog(Map<String, dynamic> branch) {
    final branchId = branch['id'] as String;
    final assignedManagers = branchManagersMap[branchId] ?? [];
    final assignedIds = assignedManagers.map((m) => m['id']).toSet();

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Управление менеджерами'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Филиал: ${branch['name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // Назначенные менеджеры
                      if (assignedManagers.isNotEmpty) ...[
                        const Text(
                          'Назначенные менеджеры:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        ...assignedManagers.map((m) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(m['full_name'] ?? 'Без имени'),
                            subtitle: Text(m['email'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _removeManager(branchId, m['id']);
                              },
                            ),
                          ),
                        )),
                        const SizedBox(height: 16),
                        const Divider(),
                      ],
                      
                      // Доступные менеджеры для добавления
                      const Text(
                        'Добавить менеджера:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      if (managers.isEmpty)
                        const Text(
                          'Нет доступных менеджеров. Сначала создайте пользователя с ролью "manager".',
                          style: TextStyle(color: Colors.orange),
                        )
                      else
                        SizedBox(
                          height: 200,
                          child: ListView(
                            shrinkWrap: true,
                            children: managers
                                .where((m) => !assignedIds.contains(m['id']))
                                .map((m) => ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey[300],
                                    child: Icon(Icons.person, color: Colors.grey[600]),
                                  ),
                                  title: Text(m['full_name'] ?? 'Без имени'),
                                  subtitle: Text(m['email'] ?? ''),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.green),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _assignManager(branchId, m['id']);
                                    },
                                  ),
                                ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Закрыть'),
                  ),
                ],
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Филиалы магазина')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add_location),
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : branches.isEmpty
              ? const Center(child: Text('Нет филиалов'))
              : ListView.builder(
                itemCount: branches.length,
                itemBuilder: (context, index) {
                  final b = branches[index];
                  final branchId = b['id'] as String;
                  final assignedManagers = branchManagersMap[branchId] ?? [];
                  // Fallback на старый способ если branch_managers пуст
                  final legacyProfile = b['profiles'] as Map<String, dynamic>?;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.store),
                      title: Text(b['name'] ?? 'Филиал'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b['latitude']?.toStringAsFixed(4)}, ${b['longitude']?.toStringAsFixed(4)}',
                          ),
                          const SizedBox(height: 4),
                          if (assignedManagers.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                ...assignedManagers.map((m) => Chip(
                                  avatar: const CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Icon(Icons.person, size: 14, color: Colors.white),
                                  ),
                                  label: Text(
                                    m['full_name'] ?? m['email'] ?? '?',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                )),
                              ],
                            )
                          else if (legacyProfile != null)
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  legacyProfile['full_name'] ?? legacyProfile['email'] ?? 'Менеджер',
                                  style: const TextStyle(color: Colors.green, fontSize: 12),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Icon(Icons.person, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  'Менеджер не назначен',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'manager') {
                            _showManagerDialog(b);
                          } else if (value == 'delete') {
                            _deleteBranch(b['id']);
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'manager',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_add),
                                    SizedBox(width: 8),
                                    Text('Назначить менеджера'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text(
                                      'Удалить',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

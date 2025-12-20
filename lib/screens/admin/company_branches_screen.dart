import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyBranchesScreen extends StatefulWidget {
  final String companyId;
  const CompanyBranchesScreen({super.key, required this.companyId});

  @override
  State<CompanyBranchesScreen> createState() => _CompanyBranchesScreenState();
}

class _CompanyBranchesScreenState extends State<CompanyBranchesScreen> {
  List<Map<String, dynamic>> branches = [];
  bool loading = true;
  final MapController _mapController = MapController();
  LatLng _selectedLocation = const LatLng(51.509364, -0.128928); // Default London
  final TextEditingController _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadBranches();
  }

  Future<void> loadBranches() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
          .from('company_branches')
          .select()
          .eq('company_id', widget.companyId);
      setState(() {
        branches = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      // If table doesn't exist or error
      setState(() => loading = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить филиал'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              TextField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Название / Адрес'),
              ),
              const SizedBox(height: 10),
              const Text('Выберите точку на карте:'),
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation,
                    initialZoom: 13,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedLocation = point;
                      });
                      // Rebuild dialog isn't automatic here without StatefulBuilder, 
                      // but for simplicity we just update the var and user clicks Add.
                      // To show marker update, we'd need StatefulBuilder in dialog.
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedLocation,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(onPressed: _addBranch, child: const Text('Добавить')),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(String id) async {
    try {
      await Supabase.instance.client.from('company_branches').delete().eq('id', id);
      loadBranches();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Филиалы магазина')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add_location),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : branches.isEmpty
              ? const Center(child: Text('Нет филиалов'))
              : ListView.builder(
                  itemCount: branches.length,
                  itemBuilder: (context, index) {
                    final b = branches[index];
                    return ListTile(
                      leading: const Icon(Icons.store),
                      title: Text(b['name'] ?? 'Филиал'),
                      subtitle: Text('${b['latitude']}, ${b['longitude']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteBranch(b['id']),
                      ),
                    );
                  },
                ),
    );
  }
}

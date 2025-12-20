// lib/screens/companies_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});
  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  List<Map<String, dynamic>> companies = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    
    loadCompanies();
  }

  Future<void> loadCompanies() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
      .from('companies')
      .select('id, name, description, company_managers!company_id(profiles(email, id))');

      setState(() {
        companies = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Компании')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CompanyFormScreen()),
          ).then((_) => loadCompanies());
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : companies.isEmpty
              ? const Center(child: Text('Нет компаний'))
              : ListView.builder(
                  itemCount: companies.length,
                  itemBuilder: (context, i) {
                    final c = companies[i];
                   final managerEmail = (c['company_managers'] as Map<String, dynamic>?)
                          ?['profiles']?['email'] as String? ??
                      '—';

                    return ListTile(
                      title: Text(c['name'] ?? 'Без названия'),
                      subtitle: Text('Менеджер: $managerEmail'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CompanyFormScreen(company: c),
                          ),
                        ).then((_) => loadCompanies());
                      },
                    );
                  },
                ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Форма создания и редактирования компании
// ──────────────────────────────────────────────────────────────
class CompanyFormScreen extends StatefulWidget {
  final Map<String, dynamic>? company;
  const CompanyFormScreen({super.key, this.company});

  @override
  State<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends State<CompanyFormScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedManagerId;
  List<Map<String, dynamic>> users = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();

    _nameCtrl.text = widget.company?['name'] ?? '';
    _descCtrl.text = widget.company?['description'] ?? '';

    // Правильное получение ID менеджера (работает и с Map, и с List)
    final managerData = widget.company?['company_managers'];

    if (managerData is Map<String, dynamic>) {
      // Новый формат — один объект
      _selectedManagerId = managerData['profiles']?['id'] as String?;
    } else if (managerData is List && managerData.isNotEmpty) {
      // Старый формат — массив
      _selectedManagerId = managerData[0]['profiles']?['id'] as String?;
    }

    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, email')
          .order('email');

      setState(() {
        users = List<Map<String, dynamic>>.from(res);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки пользователей: $e')));
      }
    }
  }

  Future<void> save() async {
    if (_nameCtrl.text.trim().isEmpty || _selectedManagerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название и выберите менеджера')),
      );
      return;
    }

    try {
      final client = Supabase.instance.client;
      final currentUserId = Supabase.instance.client.auth.currentUser!.id;

      if (widget.company == null) {
        // === СОЗДАНИЕ ===
        final companyRes = await client
            .from('companies')
            .insert({
              'name': _nameCtrl.text.trim(),
              'description': _descCtrl.text.trim(),
              'created_by': currentUserId,   // ЭТА СТРОКА РЕШАЕТ ВСЁ
            })
            .select('id')
            .single();

        await client.from('company_managers').insert({
          'user_id': _selectedManagerId,
          'company_id': companyRes['id'], // ← исправлено: было company['id']
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Компания создана!')),
          );
        }
      } else {
        // === РЕДАКТИРОВАНИЕ ===
        await client.from('companies').update({
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
        }).eq('id', widget.company!['id']);

        // Полная замена менеджера
        await client
            .from('company_managers')
            .delete()
            .eq('company_id', widget.company!['id']);

        await client.from('company_managers').insert({
          'user_id': _selectedManagerId,
          'company_id': widget.company!['id'],
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Компания обновлена!')),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.company == null ? 'Новая компания' : 'Редактировать компанию'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название компании',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            loading
                ? const CircularProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedManagerId,
                    hint: const Text('Выберите менеджера'),
                    decoration: const InputDecoration(
                      labelText: 'Менеджер',
                      border: OutlineInputBorder(),
                    ),
                    items: users.map<DropdownMenuItem<String>>((u) {
                      return DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text(u['email'] as String),
                      );
                    }).toList(),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedManagerId = value;
                      });
                    },
                  ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: save,
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
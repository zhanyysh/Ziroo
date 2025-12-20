// lib/screens/companies_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'company_branches_screen.dart';

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
  final _discountCtrl = TextEditingController();
  String? _selectedManagerId;
  List<Map<String, dynamic>> users = [];
  bool loading = true;
  File? _logoFile;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();

    _nameCtrl.text = widget.company?['name'] ?? '';
    _descCtrl.text = widget.company?['description'] ?? '';
    _discountCtrl.text = (widget.company?['discount_percentage'] ?? 0).toString();
    _logoUrl = widget.company?['logo_url'];

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

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _logoFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadLogo(String companyId) async {
    if (_logoFile == null) return _logoUrl;
    try {
      final fileExt = _logoFile!.path.split('.').last;
      final fileName = '$companyId/logo_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      await Supabase.instance.client.storage
          .from('company_logos')
          .upload(fileName, _logoFile!);
      
      final imageUrl = Supabase.instance.client.storage
          .from('company_logos')
          .getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки лого: $e')));
      return null;
    }
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
      final discount = int.tryParse(_discountCtrl.text) ?? 0;

      if (widget.company == null) {
        // === СОЗДАНИЕ ===
        final companyRes = await client
            .from('companies')
            .insert({
              'name': _nameCtrl.text.trim(),
              'description': _descCtrl.text.trim(),
              'discount_percentage': discount,
              'created_by': currentUserId,   // ЭТА СТРОКА РЕШАЕТ ВСЁ
            })
            .select('id')
            .single();
        
        final newCompanyId = companyRes['id'];
        
        // Upload logo if exists
        if (_logoFile != null) {
           final url = await _uploadLogo(newCompanyId);
           if (url != null) {
             await client.from('companies').update({'logo_url': url}).eq('id', newCompanyId);
           }
        }

        await client.from('company_managers').insert({
          'user_id': _selectedManagerId,
          'company_id': newCompanyId, // ← исправлено: было company['id']
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Компания создана!')),
          );
        }
      } else {
        // === РЕДАКТИРОВАНИЕ ===
        final companyId = widget.company!['id'];
        String? newLogoUrl = _logoUrl;
        
        if (_logoFile != null) {
           newLogoUrl = await _uploadLogo(companyId);
        }

        await client.from('companies').update({
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'discount_percentage': discount,
          'logo_url': newLogoUrl,
        }).eq('id', companyId);

        // Полная замена менеджера
        await client
            .from('company_managers')
            .delete()
            .eq('company_id', companyId);

        await client.from('company_managers').insert({
          'user_id': _selectedManagerId,
          'company_id': companyId,
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
        child: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickLogo,
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: _logoFile != null 
                    ? FileImage(_logoFile!) 
                    : (_logoUrl != null ? NetworkImage(_logoUrl!) : null) as ImageProvider?,
                  child: (_logoFile == null && _logoUrl == null) 
                    ? const Icon(Icons.add_a_photo) 
                    : null,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Логотип магазина'),
              const SizedBox(height: 20),
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
              const SizedBox(height: 16),
              TextField(
                controller: _discountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Скидка для пользователей (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
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
              const SizedBox(height: 20),
              if (widget.company != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Управление филиалами (Карта)'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompanyBranchesScreen(companyId: widget.company!['id']),
                      ),
                    );
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
      ),
    );
  }
}
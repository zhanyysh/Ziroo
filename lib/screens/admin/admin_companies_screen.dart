// lib/screens/companies_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'company_branches_screen.dart';
import 'company_events_screen.dart';
import '../../services/admin_logger.dart';

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});
  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  List<Map<String, dynamic>> companies = [];
  bool loading = true;
  String _searchQuery = '';

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
          .select('id, name, description, discount_percentage, logo_url, category');

      setState(() {
        companies = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredCompanies {
    if (_searchQuery.isEmpty) return companies;
    return companies.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final desc = (c['description'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
             desc.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredCompanies;
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Custom App Bar
          SliverAppBar(
            expandedHeight: 120,
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
                            'Компании',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${companies.length}',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Поиск компаний...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Content
          if (loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isEmpty ? 'Нет компаний' : 'Ничего не найдено',
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
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final c = filtered[i];
                    return _buildCompanyCard(c, theme);
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CompanyFormScreen()),
          ).then((_) => loadCompanies());
        },
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }

  Widget _buildCompanyCard(Map<String, dynamic> c, ThemeData theme) {
    final discount = c['discount_percentage'] ?? 0;
    final category = c['category'] as String? ?? 'Другое';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withOpacity(0.2),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CompanyFormScreen(company: c),
            ),
          ).then((_) => loadCompanies());
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Logo
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: c['logo_url'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          c['logo_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.store,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.store,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c['name'] ?? 'Без названия',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(category).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              color: _getCategoryColor(category),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-$discount%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Еда': return Colors.orange;
      case 'Одежда': return Colors.pink;
      case 'Электроника': return Colors.blue;
      case 'Услуги': return Colors.purple;
      case 'Развлечения': return Colors.red;
      default: return Colors.grey;
    }
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
  String _selectedCategory = 'Другое';
  final List<String> _categories = [
    'Еда',
    'Одежда',
    'Электроника',
    'Услуги',
    'Развлечения',
    'Другое'
  ];
  bool loading = false;
  File? _logoFile;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();

    _nameCtrl.text = widget.company?['name'] ?? '';
    _descCtrl.text = widget.company?['description'] ?? '';
    _discountCtrl.text =
        (widget.company?['discount_percentage'] ?? 0).toString();
    _logoUrl = widget.company?['logo_url'];
    _selectedCategory = widget.company?['category'] ?? 'Другое';
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        // cropStyle removed from here
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Логотип',
            toolbarColor: Colors.deepPurple,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            cropStyle: CropStyle.circle, // <-- Moved here
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
          ),
          IOSUiSettings(
            title: 'Логотип',
            cropStyle: CropStyle.circle, // <-- Moved here
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _logoFile = File(croppedFile.path);
        });
      }
    }
  }

  Future<String?> _uploadLogo(String companyId) async {
    if (_logoFile == null) return _logoUrl;
    try {
      final fileExt = _logoFile!.path.split('.').last;
      final fileName =
          '$companyId/logo_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      await Supabase.instance.client.storage
          .from('company_logos')
          .upload(fileName, _logoFile!);

      final imageUrl = Supabase.instance.client.storage
          .from('company_logos')
          .getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка загрузки лого: $e')));
      return null;
    }
  }

  Future<void> save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название компании')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final client = Supabase.instance.client;
      final currentUserId = Supabase.instance.client.auth.currentUser!.id;
      final discount = int.tryParse(_discountCtrl.text) ?? 0;

      if (widget.company == null) {
        // === СОЗДАНИЕ ===
        final companyRes =
            await client
                .from('companies')
                .insert({
                  'name': _nameCtrl.text.trim(),
                  'description': _descCtrl.text.trim(),
                  'discount_percentage': discount,
                  'created_by': currentUserId,
                  'category': _selectedCategory,
                })
                .select('id')
                .single();

        final newCompanyId = companyRes['id'];

        // Upload logo if exists
        if (_logoFile != null) {
          final url = await _uploadLogo(newCompanyId);
          if (url != null) {
            await client
                .from('companies')
                .update({'logo_url': url})
                .eq('id', newCompanyId);
          }
        }

        await AdminLogger.log(
          'create_company',
          'Создана компания: ${_nameCtrl.text}',
        );

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Компания создана!')));
        }
      } else {
        // === РЕДАКТИРОВАНИЕ ===
        final companyId = widget.company!['id'];
        String? newLogoUrl = _logoUrl;

        if (_logoFile != null) {
          newLogoUrl = await _uploadLogo(companyId);
        }

        await client
            .from('companies')
            .update({
              'name': _nameCtrl.text.trim(),
              'description': _descCtrl.text.trim(),
              'discount_percentage': discount,
              'category': _selectedCategory,
              'logo_url': newLogoUrl,
            })
            .eq('id', companyId);

        await AdminLogger.log(
          'update_company',
          'Обновлена компания: ${_nameCtrl.text}',
        );

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Компания обновлена!')));
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteCompany() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Удалить компанию?'),
            content: const Text(
              'Внимание! Все филиалы этой компании также будут удалены.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Удалить',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    setState(() => loading = true);
    try {
      final companyId = widget.company!['id'];
      final companyName = widget.company!['name'];

      // 1. Delete branches first (Manual Cascade for safety)
      await Supabase.instance.client
          .from('company_branches')
          .delete()
          .eq('company_id', companyId);

      // 2. Delete company
      await Supabase.instance.client
          .from('companies')
          .delete()
          .eq('id', companyId);

      await AdminLogger.log('delete_company', 'Удалена компания: $companyName');

      if (mounted) {
        Navigator.pop(context); // Close form
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.company == null ? 'Новая компания' : 'Редактировать компанию',
        ),
        actions: [
          if (widget.company != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: loading ? null : _deleteCompany,
            ),
        ],
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
                  backgroundImage:
                      _logoFile != null
                          ? FileImage(_logoFile!)
                          : (_logoUrl != null ? NetworkImage(_logoUrl!) : null)
                              as ImageProvider?,
                  child:
                      (_logoFile == null && _logoUrl == null)
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
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCategory = newValue!;
                  });
                },
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
              if (widget.company != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Управление филиалами (Карта)'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => CompanyBranchesScreen(
                              companyId: widget.company!['id'],
                            ),
                      ),
                    );
                  },
                ),
              if (widget.company != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: const Text('Управление акциями и ивентами'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => CompanyEventsScreen(
                              companyId: widget.company!['id'],
                            ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : save,
                  child:
                      loading
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

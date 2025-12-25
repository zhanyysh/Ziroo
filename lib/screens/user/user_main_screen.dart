import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'company_details_screen.dart';

class UserMainScreen extends StatefulWidget {
  const UserMainScreen({super.key});

  @override
  State<UserMainScreen> createState() => _UserMainScreenState();
}

class _UserMainScreenState extends State<UserMainScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _events = [];
  Set<String> _favoriteIds = {};
  bool _isLoading = true;
  
  String _selectedCategory = 'Все';
  final List<String> _categories = [
    'Все',
    'Избранное',
    'Еда',
    'Одежда',
    'Электроника',
    'Услуги',
    'Развлечения',
    'Другое'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      final companiesData = await _supabase.from('companies').select();
      
      // Загружаем избранное
      if (userId != null) {
        final favoritesData = await _supabase
            .from('user_favorites')
            .select('company_id')
            .eq('user_id', userId);
        
        _favoriteIds = (favoritesData as List)
            .map((e) => e['company_id'] as String)
            .toSet();
      }

      // Загружаем последние 5 акций
      final eventsData = await _supabase
          .from('company_events')
          .select()
          .order('created_at', ascending: false)
          .limit(5);

      if (mounted) {
        setState(() {
          _companies = List<Map<String, dynamic>>.from(companiesData);
          _events = List<Map<String, dynamic>>.from(eventsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        print('Error loading data: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFavorite(String companyId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      if (_favoriteIds.contains(companyId)) {
        _favoriteIds.remove(companyId);
      } else {
        _favoriteIds.add(companyId);
      }
    });

    try {
      if (_favoriteIds.contains(companyId)) {
        await _supabase.from('user_favorites').insert({
          'user_id': userId,
          'company_id': companyId,
        });
      } else {
        await _supabase
            .from('user_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('company_id', companyId);
      }
    } catch (e) {
      // Revert on error
      setState(() {
        if (_favoriteIds.contains(companyId)) {
          _favoriteIds.remove(companyId);
        } else {
          _favoriteIds.add(companyId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления избранного: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Главная')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // Блок новостей и акций
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Акции и новости',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    if (_events.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Пока нет активных акций'),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _events.length,
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            return Container(
                              width: 300,
                              margin: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                                image: event['image_url'] != null
                                    ? DecorationImage(
                                        image: NetworkImage(event['image_url']),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(16),
                                alignment: Alignment.bottomLeft,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event['title'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (event['description'] != null)
                                      Text(
                                        event['description'],
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Заголовок списка магазинов
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Магазины',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // Фильтр категорий
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = _selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedCategory = category;
                            });
                          }
                        },
                        selectedColor: Theme.of(context).primaryColor,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Список магазинов
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _companies.isEmpty
                    ? const SliverFillRemaining(
                        child: Center(child: Text('Список магазинов пуст')),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            // Фильтрация
                            List<Map<String, dynamic>> filteredCompanies;
                            if (_selectedCategory == 'Все') {
                              filteredCompanies = _companies;
                            } else if (_selectedCategory == 'Избранное') {
                              filteredCompanies = _companies
                                  .where((c) => _favoriteIds.contains(c['id']))
                                  .toList();
                            } else {
                              filteredCompanies = _companies
                                  .where((c) => c['category'] == _selectedCategory)
                                  .toList();
                            }
                            
                            if (index >= filteredCompanies.length) return null;
                            
                            final company = filteredCompanies[index];
                            final isFavorite = _favoriteIds.contains(company['id']);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ListTile(
                                onTap: () async {
                                  await context.push(
                                    '/home/company',
                                    extra: company,
                                  );
                                  _loadData(); // Reload to sync favorites
                                },
                                leading:
                                    company['logo_url'] != null
                                        ? CircleAvatar(
                                          backgroundImage: NetworkImage(
                                            company['logo_url'],
                                          ),
                                        )
                                    : const CircleAvatar(
                                        child: Icon(Icons.store),
                                      ),
                                title: Text(company['name'] ?? 'Без названия'),
                                subtitle: Text(
                                  company['description'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isFavorite ? Icons.favorite : Icons.favorite_border,
                                        color: isFavorite ? Colors.red : Colors.grey,
                                      ),
                                      onPressed: () => _toggleFavorite(company['id']),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green),
                                      ),
                                      child: Text(
                                        '-${company['discount_percentage']}%',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _selectedCategory == 'Все'
                              ? _companies.length
                              : (_selectedCategory == 'Избранное'
                                  ? _companies.where((c) => _favoriteIds.contains(c['id'])).length
                                  : _companies.where((c) => c['category'] == _selectedCategory).length),
                        ),
                      ),
            
            // Отступ снизу для FAB
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

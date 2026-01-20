import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class UserMainScreen extends StatefulWidget {
  const UserMainScreen({super.key});

  @override
  State<UserMainScreen> createState() => _UserMainScreenState();
}

class _UserMainScreenState extends State<UserMainScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _events = [];
  Set<String> _favoriteIds = {};
  bool _isLoading = true;
  String? _userName;
  String? _avatarUrl;
  String _searchQuery = '';
  
  String _selectedCategory = 'Все';
  final List<Map<String, dynamic>> _categories = [
    {'name': 'Все', 'icon': Icons.apps},
    {'name': 'Избранное', 'icon': Icons.favorite},
    {'name': 'Еда', 'icon': Icons.restaurant},
    {'name': 'Одежда', 'icon': Icons.checkroom},
    {'name': 'Электроника', 'icon': Icons.devices},
    {'name': 'Услуги', 'icon': Icons.build},
    {'name': 'Развлечения', 'icon': Icons.celebration},
    {'name': 'Другое', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
    });
  }

  Future<void> _loadData() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      // Загрузка профиля
      if (userId != null) {
        final profileData = await _supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', userId)
            .maybeSingle();
        
        if (profileData != null) {
          _userName = profileData['full_name'];
          _avatarUrl = profileData['avatar_url'];
        }
      }
      
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
        debugPrint('Error loading data: $e');
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
    final theme = Theme.of(context);
    final user = _supabase.auth.currentUser;
    final greeting = _getGreeting();
    final name = _userName ?? user?.userMetadata?['name'] as String? ?? 'Пользователь';
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // Header с приветствием
            SliverToBoxAdapter(
              child: Container(
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
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Avatar
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                backgroundImage: _avatarUrl != null 
                                    ? NetworkImage(_avatarUrl!) 
                                    : null,
                                child: _avatarUrl == null
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    greeting,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Notifications
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Поисковая строка
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Поиск магазинов и скидок...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Акции и новости
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🔥 Акции и новости',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_events.isNotEmpty)
                      TextButton(
                        onPressed: () {},
                        child: Text('Все', style: TextStyle(color: theme.colorScheme.primary)),
                      ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _events.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_offer_outlined, color: Colors.grey[400], size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Пока нет активных акций.\nСледите за обновлениями!',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          return _buildEventCard(event, theme);
                        },
                      ),
                    ),
            ),

            // Категории
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  'Категории',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = _selectedCategory == category['name'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(
                          category['icon'] as IconData,
                          size: 18,
                          color: isSelected ? Colors.white : theme.colorScheme.primary,
                        ),
                        label: Text(category['name'] as String),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = category['name'] as String);
                          }
                        },
                        selectedColor: theme.colorScheme.primary,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Заголовок списка магазинов
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🏪 Магазины',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_getFilteredCompanies().length} магазинов',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Список магазинов
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _getFilteredCompanies().isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _selectedCategory == 'Избранное' 
                                    ? Icons.favorite_border 
                                    : Icons.store_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedCategory == 'Избранное'
                                    ? 'Нет избранных магазинов'
                                    : 'Нет магазинов в этой категории',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final companies = _getFilteredCompanies();
                              final company = companies[index];
                              final isFavorite = _favoriteIds.contains(company['id']);
                              return _buildCompanyCard(company, isFavorite, theme);
                            },
                            childCount: _getFilteredCompanies().length,
                          ),
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredCompanies() {
    List<Map<String, dynamic>> result;
    
    // Сначала фильтруем по категории
    if (_selectedCategory == 'Все') {
      result = _companies;
    } else if (_selectedCategory == 'Избранное') {
      result = _companies.where((c) => _favoriteIds.contains(c['id'])).toList();
    } else {
      result = _companies.where((c) => c['category'] == _selectedCategory).toList();
    }
    
    // Затем фильтруем по поисковому запросу
    if (_searchQuery.isNotEmpty) {
      result = result.where((company) {
        final name = (company['name'] as String? ?? '').toLowerCase();
        final description = (company['description'] as String? ?? '').toLowerCase();
        final category = (company['category'] as String? ?? '').toLowerCase();
        
        return name.contains(_searchQuery) ||
               description.contains(_searchQuery) ||
               category.contains(_searchQuery);
      }).toList();
    }
    
    return result;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Доброй ночи 🌙';
    if (hour < 12) return 'Доброе утро ☀️';
    if (hour < 18) return 'Добрый день 👋';
    return 'Добрый вечер 🌆';
  }

  Widget _buildEventCard(Map<String, dynamic> event, ThemeData theme) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12, left: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        image: event['image_url'] != null
            ? DecorationImage(
                image: NetworkImage(event['image_url']),
                fit: BoxFit.cover,
              )
            : null,
        gradient: event['image_url'] == null
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'АКЦИЯ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              event['title'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (event['description'] != null)
              Text(
                event['description'],
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyCard(Map<String, dynamic> company, bool isFavorite, ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        await context.push('/home/company', extra: company);
        _loadData();
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Изображение / логотип
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: company['logo_url'] != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            child: Image.network(
                              company['logo_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Icon(
                                  Icons.store,
                                  size: 40,
                                  color: theme.colorScheme.primary.withOpacity(0.5),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.store,
                              size: 40,
                              color: theme.colorScheme.primary.withOpacity(0.5),
                            ),
                          ),
                  ),
                  // Скидка
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF8BC34A)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '-${company['discount_percentage']}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  // Favorite
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(company['id']),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.red : Colors.grey,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company['name'] ?? 'Без названия',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        company['description'] ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

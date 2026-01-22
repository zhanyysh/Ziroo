import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../map/map_screen.dart';

class CompanyDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const CompanyDetailsScreen({super.key, required this.company});

  @override
  State<CompanyDetailsScreen> createState() => _CompanyDetailsScreenState();
}

class _CompanyDetailsScreenState extends State<CompanyDetailsScreen> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('user_favorites')
          .select()
          .eq('user_id', userId)
          .eq('company_id', widget.company['id'])
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _isFavorite = data != null;
        });
      }
    } catch (e) {
      // ignore error
    }
  }

  Future<void> _toggleFavorite() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isFavorite = !_isFavorite);

    try {
      if (_isFavorite) {
        await Supabase.instance.client.from('user_favorites').insert({
          'user_id': userId,
          'company_id': widget.company['id'],
        });
      } else {
        await Supabase.instance.client
            .from('user_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('company_id', widget.company['id']);
      }
    } catch (e) {
      setState(() => _isFavorite = !_isFavorite); // Revert
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _loadDetails() async {
    try {
      final client = Supabase.instance.client;
      
      // Load branches
      final branchesData = await client
          .from('company_branches')
          .select()
          .eq('company_id', widget.company['id']);

      // Load events
      final eventsData = await client
          .from('company_events')
          .select()
          .eq('company_id', widget.company['id'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(branchesData);
          _events = List<Map<String, dynamic>>.from(eventsData);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _openMap({double? lat, double? lng}) {
    // Используем go_router для перехода на карту
    // Но так как карта находится в другой ветке (branch), 
    // нам нужно переключиться на нее.
    // В go_router это делается через go('/map').
    // Однако, мы хотим передать параметры (координаты).
    // ShellRoute не поддерживает передачу сложных объектов между ветками так просто.
    // Но мы можем передать query parameters.
    
    if (lat != null && lng != null) {
      // Если есть координаты, открываем карту как отдельный экран (не в табе),
      // или переходим на таб карты.
      // Вариант 1: Переход на таб карты (но тогда нужно научить MapScreen читать query params)
      // Вариант 2: Открыть карту поверх всего (как модалку или новый экран)
      
      // Давайте используем push, чтобы открыть карту поверх текущего экрана,
      // так как пользователь хочет просто посмотреть где это, а не уйти с концами на вкладку карты.
      // Для этого нам нужен роут в router.dart, который не является частью ShellRoute,
      // или просто использовать Navigator.push (что допустимо для модальных сценариев),
      // но раз мы переходим на go_router, давайте сделаем красиво.
      
      // Я добавлю '/map-view' в router.dart позже, а пока используем push
      // на существующий '/map', но это переключит вкладку.
      
      // Лучшее решение сейчас: использовать Navigator.push для открытия карты "посмотреть",
      // так как это временное действие.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => MapScreen(
                initialLocation: LatLng(lat, lng),
              ),
        ),
      );
    } else {
      // Если просто открыть карту - переключаем вкладку
      context.go('/map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final theme = Theme.of(context);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : theme.iconTheme.color,
                  ),
                  onPressed: _toggleFavorite,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  company['logo_url'] != null
                      ? Image.network(
                          company['logo_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.grey),
                        )
                      : Container(
                          color: Colors.deepPurple,
                          child: const Icon(Icons.store, size: 80, color: Colors.white),
                        ),
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          company['name'] ?? 'Магазин',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tags Row (Category, Discount)
                  Row(
                    children: [
                      if (company['category'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            company['category'],
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (company['category'] != null) const SizedBox(width: 8),
                      if (company['discount_percentage'] != null && company['discount_percentage'] > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_offer, size: 16, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '-${company['discount_percentage']}%',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Description
                  Text(
                    'О компании',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    company['description'] ?? 'Описание отсутствует',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Events Section
                  if (_events.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Акции и новости',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          return Container(
                            width: 280,
                            margin: const EdgeInsets.only(right: 16, bottom: 8),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
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
                                Expanded(
                                  flex: 3,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: event['image_url'] != null
                                        ? Image.network(
                                            event['image_url'],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.image_not_supported),
                                            ),
                                          )
                                        : Container(
                                            color: theme.colorScheme.surfaceContainerHighest,
                                            child: const Center(child: Icon(Icons.image, size: 40)),
                                          ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          event['title'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        if (event['description'] != null)
                                          Text(
                                            event['description'],
                                            style: theme.textTheme.bodySmall,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Branches Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Филиалы',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('На карте'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_branches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Нет информации о филиалах',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _branches.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        return Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.location_on, color: theme.colorScheme.primary),
                            ),
                            title: Text(
                              branch['name'] ?? 'Филиал',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                branch['address'] ?? '${branch['latitude']}, ${branch['longitude']}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: () {
                              final lat = branch['latitude'] as double?;
                              final lng = branch['longitude'] as double?;
                              _openMap(lat: lat, lng: lng);
                            },
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

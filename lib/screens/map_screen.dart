import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const MapScreen({super.key, this.initialLocation});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _filteredBranches = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  final FocusNode _searchFocusNode = FocusNode();
  bool _isMapReady = false;

  // StreamController не нужен, так как mapController имеет свой стрим событий

  @override
  void initState() {
    super.initState();
    _loadAllBranches();
    _determinePosition();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _transliterate(String text) {
    const map = {
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'yo',
      'ж': 'zh',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'х': 'kh',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'shch',
      'ъ': '',
      'ы': 'y',
      'ь': '',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
    };

    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i].toLowerCase();
      sb.write(map[char] ?? char);
    }
    return sb.toString();
  }

  // Нормализация для нечеткого поиска (kh -> h, ts -> c, zh -> j)
  String _normalize(String text) {
    return text
        .replaceAll('kh', 'h')
        .replaceAll('ts', 'c')
        .replaceAll('zh', 'j')
        .replaceAll('yo', 'e');
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    // Транслитерируем и нормализуем запрос
    final queryNormalized = _normalize(_transliterate(query));

    setState(() {
      _filteredBranches =
          _branches.where((branch) {
            final companyRaw = branch['companies'];
            final Map<String, dynamic>? company =
                companyRaw is List
                    ? (companyRaw.isNotEmpty ? companyRaw.first : null)
                    : companyRaw as Map<String, dynamic>?;

            final companyName =
                (company?['name'] as String? ?? '').toLowerCase();
            final companyDesc =
                (company?['description'] as String? ?? '').toLowerCase();
            final branchName = (branch['name'] as String? ?? '').toLowerCase();

            // 1. Прямой поиск (как есть)
            if (companyName.contains(query) ||
                branchName.contains(query) ||
                companyDesc.contains(query)) {
              return true;
            }

            // 2. Поиск с нормализацией (транслит + упрощение)
            final companyNameNorm = _normalize(_transliterate(companyName));
            final companyDescNorm = _normalize(_transliterate(companyDesc));
            final branchNameNorm = _normalize(_transliterate(branchName));

            if (companyNameNorm.contains(queryNormalized) ||
                branchNameNorm.contains(queryNormalized) ||
                companyDescNorm.contains(queryNormalized)) {
              return true;
            }

            return false;
          }).toList();
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Проверяем включена ли геолокация
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        // Показываем диалог как в 2ГИС
        final openSettings = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Геолокация выключена'),
                content: const Text(
                  'Для определения вашего местоположения необходимо включить геолокацию.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Включить'),
                  ),
                ],
              ),
        );

        if (openSettings == true) {
          await Geolocator.openLocationSettings();
        }
      }
      return;
    }

    // 2. Проверяем разрешения
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Разрешение на геолокацию отклонено')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Доступ запрещен'),
                content: const Text(
                  'Вы запретили доступ к геолокации навсегда. Пожалуйста, разрешите доступ в настройках приложения.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Geolocator.openAppSettings();
                    },
                    child: const Text('Настройки'),
                  ),
                ],
              ),
        );
      }
      return;
    }

    // 3. Получаем позицию с таймаутом
    try {
      // Сначала пробуем получить последнюю известную позицию (это быстро)
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _currentPosition = LatLng(
            lastPosition.latitude,
            lastPosition.longitude,
          );
        });
        if (_isMapReady) {
          _mapController.move(_currentPosition!, 15);
        }
      }

      // Затем пробуем получить точную позицию
      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        if (_isMapReady) {
          _mapController.move(_currentPosition!, 15);
        }
      }
    } catch (e) {
      print("Error getting location: $e");
      if (mounted && _currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось определить местоположение. Проверьте GPS.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadAllBranches() async {
    try {
      // Загружаем филиалы вместе с данными о компании (логотип, название, скидка, описание)
      final data = await Supabase.instance.client
          .from('company_branches')
          .select(
            '*, companies(name, logo_url, discount_percentage, description)',
          );

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(data);
          _filteredBranches = _branches;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        // Не показываем ошибку пользователю слишком навязчиво, если просто нет данных
        print('Ошибка загрузки карты: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Stack(
        children: [
          // Map
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildMap(theme),
          
          // Search bar overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
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
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Поиск магазинов и скидок...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
          ),
          
          // My location button
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(Icons.my_location, color: theme.colorScheme.primary),
                    onPressed: () {
                      if (_currentPosition != null) {
                        if (_isMapReady) {
                          _mapController.move(_currentPosition!, 15);
                        }
                      } else {
                        _determinePosition();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(ThemeData theme) {
    return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      onMapReady: () {
                        _isMapReady = true;
                        if (widget.initialLocation != null) {
                          _mapController.move(widget.initialLocation!, 16);
                        } else if (_currentPosition != null) {
                          _mapController.move(_currentPosition!, 15);
                        }
                      },
                      // Центр карты: Бишкек, Кыргызстан
                      initialCenter: widget.initialLocation ?? const LatLng(42.8746, 74.5698),
                      initialZoom: widget.initialLocation != null ? 16 : 12,
                      maxZoom:
                          18.4, // Увеличиваем зум, чтобы было видно детали как в 2ГИС
                      interactionOptions: InteractionOptions(
                        flags:
                            InteractiveFlag.all, // Разрешаем вращение и наклон
                      ),
                    ),
                    children: [
                      TileLayer(
                        // Используем более детальные тайлы (OSM), они светлее и привычнее
                        urlTemplate:
                            Theme.of(context).brightness == Brightness.dark
                                ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        // Для светлой темы берем стандартный OSM (похож на 2ГИС деталями)
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'com.example.applearn',
                      ),
                      MarkerLayer(
                        markers: [
                          if (_currentPosition != null)
                            Marker(
                              point: _currentPosition!,
                              width: 60,
                              height: 60,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.blue,
                                    width: 2,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.person_pin_circle,
                                    color: Colors.blue,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          ..._filteredBranches
                              .map((branch) {
                                final lat = branch['latitude'] as double?;
                                final lng = branch['longitude'] as double?;
                                final company =
                                    branch['companies']
                                        as Map<String, dynamic>?;
                                final logoUrl = company?['logo_url'] as String?;
                                final name = company?['name'] as String? ?? '';
                                final isVip = branch['is_vip'] == true;

                                if (lat == null || lng == null) return null;

                                final isBigShop =
                                    isVip ||
                                    (logoUrl != null && logoUrl.isNotEmpty);

                                return Marker(
                                  point: LatLng(lat, lng),
                                  width: isBigShop ? 120 : 40,
                                  height: isBigShop ? 80 : 40,
                                  child: GestureDetector(
                                    onTap: () => _showBranchDetails(branch),
                                    child: _buildMarkerIcon(
                                      logoUrl,
                                      name,
                                      isBigShop,
                                    ),
                                  ),
                                );
                              })
                              .whereType<Marker>()
                              .toList(),
                        ],
                      ),
                    ],
                  );
  }

  void _showBranchDetails(Map<String, dynamic> branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BranchDetailsSheet(
          branch: branch,
          onBuildRoute: () {
            final lat = branch['latitude'] as double?;
            final lng = branch['longitude'] as double?;
            if (lat != null && lng != null) {
              Navigator.pop(ctx);
              _openExternalMap(LatLng(lat, lng));
            }
          },
        );
      },
    );
  }

  Widget _buildSearchResultsList(ThemeData theme) {
    if (!_searchFocusNode.hasFocus || _searchController.text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 16,
      right: 16,
      bottom: 100,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: _filteredBranches.isEmpty
            ? const Center(child: Text('Ничего не найдено'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filteredBranches.length,
                itemBuilder: (context, index) {
                  final branch = _filteredBranches[index];
                  final company = branch['companies'] as Map<String, dynamic>?;
                  final companyName = company?['name'] as String? ?? 'Компания';
                  final branchName = branch['name'] as String? ?? 'Филиал';
                  final logoUrl = company?['logo_url'] as String?;
                  final lat = branch['latitude'] as double?;
                  final lng = branch['longitude'] as double?;
                  final discount = company?['discount_percentage'] as int?;

                  return ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: logoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(logoUrl, fit: BoxFit.cover),
                            )
                          : Icon(Icons.store, color: theme.colorScheme.primary),
                    ),
                    title: Text(companyName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(branchName),
                    trailing: discount != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '-$discount%',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () {
                      if (lat != null && lng != null) {
                        _mapController.move(LatLng(lat, lng), 15);
                        _searchFocusNode.unfocus();
                        _showBranchDetails(branch);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _buildMarkerIcon(String? logoUrl, String name, bool isBigShop) {
    if (isBigShop) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00A2FF),
                  width: 2,
                ), // Голубая обводка
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00A2FF).withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                backgroundColor: Colors.black,
                child:
                    logoUrl == null
                        ? const Icon(Icons.star, color: Colors.white)
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    // Маленькие точки для обычных филиалов (без лого)
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        border: Border.all(color: const Color(0xFF00A2FF), width: 2),
      ),
      child: const Center(
        child: Icon(Icons.circle, color: Color(0xFF00A2FF), size: 15),
      ),
    );
  }

  Future<void> _openExternalMap(LatLng destination) async {
    final lat = destination.latitude;
    final lng = destination.longitude;

    // 1. Пробуем открыть 2ГИС (dgis://)
    final dgisUrl = Uri.parse(
      "dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat",
    );

    // 2. Пробуем Google Maps (google.navigation:)
    final googleMapsUrl = Uri.parse("google.navigation:q=$lat,$lng&mode=d");

    // 3. Универсальный geo: URI (для Яндекс.Карт и других)
    final geoUrl = Uri.parse("geo:$lat,$lng?q=$lat,$lng");

    // 4. Веб-версия Google Maps (fallback)
    final webUrl = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng",
    );

    try {
      if (await canLaunchUrl(dgisUrl)) {
        await launchUrl(dgisUrl);
      } else if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(geoUrl)) {
        await launchUrl(geoUrl);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось открыть карту: $e')));
      }
    }
  }
}

class BranchDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> branch;
  final VoidCallback onBuildRoute; // Callback для построения маршрута

  const BranchDetailsSheet({
    super.key,
    required this.branch,
    required this.onBuildRoute,
  });

  @override
  State<BranchDetailsSheet> createState() => _BranchDetailsSheetState();
}

class _BranchDetailsSheetState extends State<BranchDetailsSheet> {
  double _currentRating = 0;
  double _averageRating = 0;
  int _ratingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRatings();
  }

  Future<void> _fetchRatings() async {
    try {
      final branchId = widget.branch['id'];
      final userId = Supabase.instance.client.auth.currentUser?.id;

      // 1. Получаем все оценки этого филиала
      final ratingsResponse = await Supabase.instance.client
          .from('branch_ratings')
          .select('rating, user_id')
          .eq('branch_id', branchId);

      final ratings = List<Map<String, dynamic>>.from(ratingsResponse);

      if (ratings.isNotEmpty) {
        final total = ratings.fold<double>(
          0,
          (sum, item) => sum + (item['rating'] as int),
        );
        _averageRating = total / ratings.length;
        _ratingCount = ratings.length;
      }

      // 2. Ищем оценку текущего пользователя
      if (userId != null) {
        final myRating = ratings.firstWhere(
          (r) => r['user_id'] == userId,
          orElse: () => {},
        );
        if (myRating.isNotEmpty) {
          _currentRating = (myRating['rating'] as int).toDouble();
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      print('Error fetching ratings: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitRating(double rating) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Войдите, чтобы оценить')));
        return;
      }

      await Supabase.instance.client.from('branch_ratings').upsert({
        'user_id': userId,
        'branch_id': widget.branch['id'],
        'rating': rating.toInt(),
      }, onConflict: 'user_id, branch_id');

      // Обновляем данные
      _fetchRatings();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Спасибо за оценку!')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.branch['companies'] as Map<String, dynamic>?;
    final name = company?['name'] ?? 'Магазин';
    final address = widget.branch['name'] ?? 'Адрес не указан';
    final discount = company?['discount_percentage'] ?? 0;
    final logoUrl = company?['logo_url'];

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (logoUrl != null)
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(logoUrl),
                  ),
                )
              else
                const Center(
                  child: Icon(Icons.store, size: 80, color: Colors.deepPurple),
                ),
              const SizedBox(height: 15),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Text(
                address,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Блок рейтинга
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Text(
                      _averageRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    RatingBarIndicator(
                      rating: _averageRating,
                      itemBuilder:
                          (context, index) =>
                              const Icon(Icons.star, color: Colors.amber),
                      itemCount: 5,
                      itemSize: 20.0,
                      direction: Axis.horizontal,
                    ),
                    Text(
                      '$_ratingCount оценок',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Ваша оценка:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Center(
                child: RatingBar.builder(
                  initialRating: _currentRating,
                  minRating: 1,
                  direction: Axis.horizontal,
                  allowHalfRating: false,
                  itemCount: 5,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                  itemBuilder:
                      (context, _) =>
                          const Icon(Icons.star, color: Colors.amber),
                  onRatingUpdate: _submitRating,
                ),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const Text(
                'Отзывы',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _ReviewsSection(branchId: widget.branch['id']),

              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: widget.onBuildRoute,
                      icon: const Icon(Icons.directions),
                      label: const Text('Маршрут'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.percent, color: Colors.white),
                          const SizedBox(width: 10),
                          Text(
                            '$discount%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class _ReviewsSection extends StatefulWidget {
  final String branchId;

  const _ReviewsSection({required this.branchId});

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final data = await Supabase.instance.client
          .from('branch_reviews')
          .select('*, profiles:user_id(email, avatar_url)')
          .eq('branch_id', widget.branchId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(data);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _addReview() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оставить отзыв')),
      );
      return;
    }

    if (_commentController.text.trim().isEmpty) return;

    // Optimistic update (optional, but good for UX)
    // For now, just show loading or clear immediately
    FocusScope.of(context).unfocus(); // Hide keyboard

    try {
      await Supabase.instance.client.from('branch_reviews').insert({
        'branch_id': widget.branchId,
        'user_id': user.id,
        'comment': _commentController.text.trim(),
        'rating': 5,
      });

      _commentController.clear();
      await _loadReviews(); // Reload to show the new review

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Отзыв опубликован')));
      }
    } catch (e) {
      print('Error adding review: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'Ошибка загрузки отзывов: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          // Input field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    hintText: 'Напишите отзыв...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                  ),
                  onSubmitted: (_) => _addReview(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _addReview,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Reviews list
          if (_reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Нет отзывов', style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reviews.length,
              itemBuilder: (context, index) {
                final review = _reviews[index];
                final profile = review['profiles'] as Map<String, dynamic>?;
                final email = profile?['email'] as String? ?? 'Аноним';
                final avatarUrl = profile?['avatar_url'] as String?;
                final comment = review['comment'] as String? ?? '';
                final date = DateTime.parse(review['created_at']).toLocal();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(email.split('@')[0]),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comment),
                      Text(
                        '${date.day}.${date.month}.${date.year}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

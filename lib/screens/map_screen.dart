import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

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

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBranches = _branches.where((branch) {
        final company = branch['companies'] as Map<String, dynamic>?;
        final companyName = (company?['name'] as String? ?? '').toLowerCase();
        final branchName = (branch['name'] as String? ?? '').toLowerCase();
        return companyName.contains(query) || branchName.contains(query);
      }).toList();
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return;
    } 

    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentPosition!, 15);
      }
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  Future<void> _loadAllBranches() async {
    try {
      // Загружаем филиалы вместе с данными о компании (логотип, название, скидка)
      final data = await Supabase.instance.client
          .from('company_branches')
          .select('*, companies(name, logo_url, discount_percentage)');

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
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: 'Поиск магазина...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                    },
                  )
                : const Icon(Icons.search),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_currentPosition != null) {
            _mapController.move(_currentPosition!, 15);
          } else {
            _determinePosition();
          }
        },
        child: const Icon(Icons.my_location),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    // Центр карты: Бишкек, Кыргызстан
                    initialCenter: LatLng(42.8746, 74.5698),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      // Switch map style based on theme
                      urlTemplate: Theme.of(context).brightness == Brightness.dark
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                          : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
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
                                border: Border.all(color: Colors.blue, width: 2),
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
                                  branch['companies'] as Map<String, dynamic>?;
                              final logoUrl = company?['logo_url'] as String?;
                              final name = company?['name'] as String? ?? '';
                              final isVip = branch['is_vip'] == true;

                              if (lat == null || lng == null) return null;

                              final isBigShop =
                                  isVip || (logoUrl != null && logoUrl.isNotEmpty);

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
                ),
                if (_searchController.text.isNotEmpty && _searchFocusNode.hasFocus)
                  Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _filteredBranches.isEmpty
                        ? const Center(child: Text('Ничего не найдено'))
                        : ListView.builder(
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              final company =
                                  branch['companies'] as Map<String, dynamic>?;
                              final companyName =
                                  company?['name'] as String? ?? 'Компания';
                              final branchName =
                                  branch['name'] as String? ?? 'Филиал';
                              final logoUrl = company?['logo_url'] as String?;
                              final lat = branch['latitude'] as double?;
                              final lng = branch['longitude'] as double?;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: logoUrl != null
                                      ? NetworkImage(logoUrl)
                                      : null,
                                  child: logoUrl == null
                                      ? const Icon(Icons.store)
                                      : null,
                                ),
                                title: Text(companyName),
                                subtitle: Text(branchName),
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
              ],
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

  void _showBranchDetails(Map<String, dynamic> branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Позволяет шторке быть выше
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BranchDetailsSheet(branch: branch),
    );
  }
}

class BranchDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> branch;
  const BranchDetailsSheet({super.key, required this.branch});

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
            0, (sum, item) => sum + (item['rating'] as int));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Войдите, чтобы оценить')),
        );
        return;
      }

      await Supabase.instance.client.from('branch_ratings').upsert(
        {
          'user_id': userId,
          'branch_id': widget.branch['id'],
          'rating': rating.toInt(),
        },
        onConflict: 'user_id, branch_id',
      );

      // Обновляем данные
      _fetchRatings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Спасибо за оценку!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
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
                    child: Icon(Icons.store, size: 80, color: Colors.deepPurple)),
              const SizedBox(height: 15),
              Text(
                name,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                      itemBuilder: (context, index) => const Icon(
                        Icons.star,
                        color: Colors.amber,
                      ),
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
                  itemBuilder: (context, _) => const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onRatingUpdate: _submitRating,
                ),
              ),

              const SizedBox(height: 30),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
                      'Скидка $discount%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

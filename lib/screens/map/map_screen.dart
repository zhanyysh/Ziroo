import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart'; // Added for Clustering
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Added for Debouncing

import 'widgets/branch_details_sheet.dart';

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
  Timer? _debounce; // Timer for API debouncing

  // New variables
  bool _isListView = false; // Toggle for List View
  static const String _prefLatKey = 'map_last_lat';
  static const String _prefLngKey = 'map_last_lng';
  static const String _prefZoomKey = 'map_last_zoom';

  @override
  void initState() {
    super.initState();
    _loadSavedPosition();
    // _loadAllBranches(); // Removed: We load on map ready/move now
    _determinePosition();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPosition() async {
    if (widget.initialLocation != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_prefLatKey);
      final lng = prefs.getDouble(_prefLngKey);
      
      if (lat != null && lng != null && mounted) {
        // Position loaded, waiting for map ready to move
      }
    } catch (e) {
      debugPrint('Error loading map prefs: $e');
    }
  }

  Future<void> _savePosition(MapCamera camera) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefLatKey, camera.center.latitude);
      await prefs.setDouble(_prefLngKey, camera.center.longitude);
      await prefs.setDouble(_prefZoomKey, camera.zoom);
    } catch (_) {}
  }

  String _transliterate(String text) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
      'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
      'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
      'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
      'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    };

    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i].toLowerCase();
      sb.write(map[char] ?? char);
    }
    return sb.toString();
  }

  String _normalize(String text) {
    return text
        .replaceAll('kh', 'h')
        .replaceAll('ts', 'c')
        .replaceAll('zh', 'j')
        .replaceAll('yo', 'e');
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final query = _searchController.text.toLowerCase().trim();
      
      if (query.isEmpty) {
        // Если поиск очистили - возвращаемся к режиму Viewport Loading
        _fetchVisibleBranches();
        return;
      }

      setState(() => _loading = true);

      try {
        // Выполняем Глобальный Поиск через RPC
        final data = await Supabase.instance.client.rpc('search_branches', params: {
          'query_text': query,
          'user_lat': _currentPosition?.latitude,
          'user_lng': _currentPosition?.longitude,
        });

        if (mounted) {
          final results = List<Map<String, dynamic>>.from(data);
          
          setState(() {
            _branches = results;
            _filteredBranches = results; // Показываем то, что нашли
            _loading = false;
            // _isListView = true; // Убрали автоматическое переключение на список, как просил пользователь
          });

          // Если есть результаты, подгоняем карту под них
          if (results.isNotEmpty) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Найдено филиалов: ${results.length}')),
             );

             if (results.length == 1) {
               final lat = results[0]['latitude'] as double?;
               final lng = results[0]['longitude'] as double?;
               if (lat != null && lng != null) {
                 _mapController.move(LatLng(lat, lng), 17);
               }
             } else {
               // Calculate bounds
               double? minLat, maxLat, minLng, maxLng;
               for (var r in results) {
                 final lat = r['latitude'] as double?;
                 final lng = r['longitude'] as double?;
                 if (lat == null || lng == null) continue;
                 
                 if (minLat == null || lat < minLat) minLat = lat;
                 if (maxLat == null || lat > maxLat) maxLat = lat;
                 if (minLng == null || lng < minLng) minLng = lng;
                 if (maxLng == null || lng > maxLng) maxLng = lng;
               }

               if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
                 // Add padding
                 final bounds = LatLngBounds(
                   LatLng(minLat, minLng),
                   LatLng(maxLat, maxLng),
                 );
                 
                 _mapController.fitCamera(
                   CameraFit.bounds(
                     bounds: bounds,
                     padding: const EdgeInsets.all(50),
                   ),
                 );
               }
             }
          }
        }
      } catch (e) {
        debugPrint('Search error: $e');
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _debouncedFetch() {
    // Не обновляем Viewport, если идет поиск (текст в поле)
    if (_searchController.text.isNotEmpty) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchVisibleBranches();
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Геолокация выключена'),
            content: const Text('Для определения местоположения включите геолокацию.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Включить')),
            ],
          ),
        );

        if (openSettings == true) {
          await Geolocator.openLocationSettings();
        }
      }
      return;
    }

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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Геолокация запрещена навсегда. Разрешите в настройках.')));
      }
      return;
    }

    try {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _currentPosition = LatLng(lastPosition.latitude, lastPosition.longitude);
        });
        if (_isMapReady) {
          _mapController.move(_currentPosition!, 15);
        }
      }

      final position = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        if (_isMapReady) {
          _mapController.move(_currentPosition!, 15);
        }
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  Future<void> _fetchVisibleBranches() async {
    if (!mounted || !_isMapReady) return;

    final bounds = _mapController.camera.visibleBounds;
    final zoom = _mapController.camera.zoom;

    try {
      final data = await Supabase.instance.client.rpc('get_branches_in_view', params: {
        'min_lat': bounds.south,
        'max_lat': bounds.north,
        'min_lng': bounds.west,
        'max_lng': bounds.east,
        'zoom_level': zoom,
      });

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(data);
          // Re-apply search filter if active
          if (_searchController.text.isNotEmpty) {
            _onSearchChanged();
          } else {
            _filteredBranches = _branches;
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching viewport branches: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /*
  Future<void> _loadAllBranches() async {
    try {
      final data = await Supabase.instance.client
          .from('company_branches')
          .select('*, companies(name, logo_url, discount_percentage, description)');

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(data);
          _filteredBranches = []; // Start with empty map
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        debugPrint('Error loading map data: $e');
      }
    }
  }
  */

  Future<void> _showNearbyBranches() async {
    if (_currentPosition == null) {
      await _determinePosition();
    }

    if (_currentPosition != null && _isMapReady) {
      _mapController.move(_currentPosition!, 15);
      // Logic: Moving triggers onPositionChanged -> calls _debouncedFetch -> loads objects nearby
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Поиск объектов рядом...'), duration: Duration(seconds: 1)),
      );
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.near_me, size: 16, color: Colors.white),
                  label: const Text('Рядом', style: TextStyle(color: Colors.white)),
                  backgroundColor: Colors.green,
                  onPressed: _showNearbyBranches,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('🏢 Все'),
                   onPressed: () {
                     setState(() {
                        _filteredBranches = _branches;
                     });
                   },
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
           FloatingActionButton(
            heroTag: 'list_toggle',
            onPressed: () {
              setState(() {
                _isListView = !_isListView;
              });
            },
            child: Icon(_isListView ? Icons.map : Icons.list),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'my_location',
            onPressed: () {
              if (_currentPosition != null) {
                if (_isMapReady) {
                  _mapController.move(_currentPosition!, 15);
                }
              } else {
                _determinePosition();
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          // MAP LAYER
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              onMapReady: () async {
                _isMapReady = true;
                
                if (widget.initialLocation != null) {
                  _mapController.move(widget.initialLocation!, 16);
                } else {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final savedLat = prefs.getDouble(_prefLatKey);
                    final savedLng = prefs.getDouble(_prefLngKey);
                    final savedZoom = prefs.getDouble(_prefZoomKey);

                    if (savedLat != null && savedLng != null) {
                      _mapController.move(LatLng(savedLat, savedLng), savedZoom ?? 12);
                    } else if (_currentPosition != null) {
                      _mapController.move(_currentPosition!, 15);
                    }
                  } catch (_) {}
                }
                
                // Fetch initial data after camera move (with slight delay for bounds)
                Future.delayed(const Duration(milliseconds: 500), _fetchVisibleBranches);
              },
              initialCenter: widget.initialLocation ?? const LatLng(42.8746, 74.5698),
              initialZoom: widget.initialLocation != null ? 16 : 12,
              maxZoom: 18.4,
              onPositionChanged: (camera, hasGesture) {
                  if (hasGesture) {
                    _savePosition(camera);
                  }
                  _debouncedFetch();
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: Theme.of(context).brightness == Brightness.dark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.applearn',
              ),
              // Слой местоположения пользователя (Не кластеризуется)
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
                          child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 30),
                        ),
                      ),
                    ),
                ],
              ),
              // Слой маркеров магазинов (Кластеризация)
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 80,
                  size: const Size(40, 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 18,
                  markers: _filteredBranches.map((branch) {
                    final lat = branch['latitude'] as double?;
                    final lng = branch['longitude'] as double?;
                    final company = branch['companies'] as Map<String, dynamic>?;
                    final logoUrl = company?['logo_url'] as String?;
                    final name = company?['name'] as String? ?? '';
                    final isVip = branch['is_vip'] == true;

                    if (lat == null || lng == null) return null;

                    final isBigShop = isVip || (logoUrl != null && logoUrl.isNotEmpty);

                    return Marker(
                      point: LatLng(lat, lng),
                      width: isBigShop ? 120 : 40,
                      height: isBigShop ? 80 : 40,
                      child: GestureDetector(
                        onTap: () => _showBranchDetails(branch),
                        child: _buildMarkerIcon(logoUrl, name, isBigShop),
                      ),
                    );
                  }).whereType<Marker>().toList(),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.green,
                        border: Border.all(color: Colors.white, width: 2),
                         boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(2, 2))
                        ],
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          // LOADING OVERLAY (On top of map)
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.2),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),

          // LIST VIEW LAYER (OVERLAY)
          if (_isListView)
            Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _filteredBranches.isEmpty
                        ? const Center(child: Text('Магазины не найдены'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              final company = branch['companies'] as Map<String, dynamic>?;
                              final name = company?['name'] as String? ?? 'Магазин';
                              final address = branch['name'] as String? ?? '';
                              final logoUrl = company?['logo_url'] as String?;
                              final desc = company?['description'] as String? ?? '';
                                
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                                    child: logoUrl == null ? const Icon(Icons.store) : null,
                                  ),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (address.isNotEmpty) Text(address),
                                      if (desc.isNotEmpty) 
                                        Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, 
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    setState(() {
                                      _isListView = false;
                                    });
                                    final lat = branch['latitude'] as double?;
                                    final lng = branch['longitude'] as double?;
                                    if (lat != null && lng != null) {
                                      _mapController.move(LatLng(lat, lng), 16);
                                      _showBranchDetails(branch);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),

                // Compass
                if (!_isListView)
                  Positioned(
                    top: 100,
                    right: 16,
                    child: StreamBuilder<MapEvent>(
                      stream: _mapController.mapEventStream,
                      builder: (context, snapshot) {
                        final rotation = _mapController.camera.rotation;
                        if (rotation == 0) return const SizedBox.shrink();

                        return FloatingActionButton.small(
                          heroTag: 'compass',
                          backgroundColor: Theme.of(context).cardColor,
                          onPressed: () {
                            _mapController.rotate(0);
                          },
                          child: Transform.rotate(
                            angle: rotation * (3.14159 / 180),
                            child: const Icon(Icons.navigation, color: Colors.redAccent),
                          ),
                        );
                      },
                    ),
                  ),
                  
                if (_searchController.text.isNotEmpty && _searchFocusNode.hasFocus && !_isListView)
                  Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _filteredBranches.isEmpty
                        ? const Center(child: Text('Ничего не найдено'))
                        : ListView.builder(
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              final company = branch['companies'] as Map<String, dynamic>?;
                              final companyName = company?['name'] as String? ?? 'Компания';
                              final branchName = branch['name'] as String? ?? 'Филиал';
                              final logoUrl = company?['logo_url'] as String?;
                              final lat = branch['latitude'] as double?;
                              final lng = branch['longitude'] as double?;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                                  child: logoUrl == null ? const Icon(Icons.store) : null,
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
                border: Border.all(color: const Color(0xFF00A2FF), width: 2),
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
                child: logoUrl == null ? const Icon(Icons.star, color: Colors.white) : null,
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
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
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

    final dgisUrl = Uri.parse("dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat");
    final googleMapsUrl = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    final geoUrl = Uri.parse("geo:$lat,$lng?q=$lat,$lng"); // Universal geo scheme
    final webUrl = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть карту: $e')));
      }
    }
  }

  void _showBranchDetails(Map<String, dynamic> branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BranchDetailsSheet(
        branch: branch,
        onBuildRoute: () {
          final lat = branch['latitude'] as double?;
          final lng = branch['longitude'] as double?;
          if (lat != null && lng != null) {
            Navigator.pop(ctx);
            _openExternalMap(LatLng(lat, lng));
          }
        },
      ),
    );
  }
}

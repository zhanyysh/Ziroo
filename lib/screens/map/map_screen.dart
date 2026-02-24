import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;

import 'widgets/branch_details_sheet.dart';
import 'map_manager.dart';
import '../../models/branch.dart';
import '../../services/location_service.dart';

class MapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const MapScreen({super.key, this.initialLocation});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapManager _mapManager = MapManager();
  final LocationService _locationService = LocationService();

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  final FocusNode _searchFocusNode = FocusNode();
  bool _isMapReady = false;

  bool _isListView = false;
  static const String _prefLatKey = 'map_last_lat';
  static const String _prefLngKey = 'map_last_lng';
  static const String _prefZoomKey = 'map_last_zoom';

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<CompassEvent>? _compassStreamSubscription;
  bool _isFollowingUser = false;
  double _currentHeading = 0.0;

  List<Marker> _markers = [];
  final Map<Key, Branch> _markerBranchMap = {};

  // Кэш маркеров для оптимизации: id -> Marker
  final Map<String, Marker> _markerCache = {};

  @override
  void initState() {
    super.initState();
    _loadSavedPosition();
    _determinePosition();
    _startCompass();
    _searchController.addListener(_onSearchChanged);
    _mapManager.addListener(_onManagerUpdate);
  }

  @override
  void dispose() {
    _mapManager.removeListener(_onManagerUpdate);
    _mapManager.disposeManager();
    _positionStreamSubscription?.cancel();
    _compassStreamSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (!mounted) return;

    _updateMarkers();
    setState(() {
      if (_mapManager.branches.isNotEmpty &&
          _searchController.text.isNotEmpty &&
          !_mapManager.loading) {
        if (_mapManager.filteredBranches.length == 1) {
          final b = _mapManager.filteredBranches.first;
          final lat = b.latitude;
          final lng = b.longitude;
          if (lat != null && lng != null) {
            _mapController.move(LatLng(lat, lng), 17);
          }
        } else if (_mapManager.filteredBranches.isNotEmpty &&
            _mapManager.filteredBranches.length < 10) {
          _fitCameraToResults(_mapManager.filteredBranches);
        }
      }
    });
  }

  void _startCompass() {
    _compassStreamSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      final heading = event.heading;
      if (heading != null) {
        setState(() {
          _currentHeading = heading;
        });
      }
    });
  }

  Future<void> _loadSavedPosition() async {
    if (widget.initialLocation != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_prefLatKey);
      final lng = prefs.getDouble(_prefLngKey);
      if (lat != null && lng != null && mounted) {
        // Loaded
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

  void _updateMarkers() {
    final newMarkers = <Marker>[];
    _markerBranchMap.clear();
    final Set<String> currentIds = {}; // Для отслеживания активных ID

    final branches = _mapManager.filteredBranches;

    for (var branch in branches) {
      final lat = branch.latitude;
      final lng = branch.longitude;

      // Пропускаем невалидные координаты
      if (lat == null || lng == null) continue;

      final id = branch.id.toString();
      currentIds.add(id);

      final key = ValueKey(id);
      _markerBranchMap[key] = branch;

      // ОПТИМИЗАЦИЯ: Если маркер уже есть в кэше, берем его
      if (_markerCache.containsKey(id)) {
        newMarkers.add(_markerCache[id]!);
        continue;
      }

      // Если нет - создаем новый
      final logoUrl = branch.company?.logoUrl;
      final name = branch.company?.name ?? '';
      final priority = branch.mapPriority;

      double width = 20;
      double height = 20;

      if (priority == 1) {
        width = 160;
        height = 60;
      } else if (priority == 2) {
        width = 50;
        height = 50;
      }

      final marker = Marker(
        key: key,
        point: LatLng(lat, lng),
        width: width,
        height: height,
        child: _buildMarkerIcon(logoUrl, name, priority),
      );

      _markerCache[id] = marker;
      newMarkers.add(marker);
    }

    // Очистка кэша от старых маркеров, которых больше нет в выдаче
    _markerCache.removeWhere((id, _) => !currentIds.contains(id));

    _markers = newMarkers;
  }

  void _onSearchChanged() {
    final text = _searchController.text.toLowerCase().trim();

    if (text.isEmpty) {
      if (_isMapReady) {
        _fetchVisibleBranches();
      }
      return;
    }

    _mapManager.searchBranches(
      text,
      userLat: _currentPosition?.latitude,
      userLng: _currentPosition?.longitude,
    );
  }

  void _fitCameraToResults(List<Branch> results) {
    if (results.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;
    for (var r in results) {
      final lat = r.latitude;
      final lng = r.longitude;
      if (lat == null || lng == null) continue;
      if (minLat == null || lat < minLat) minLat = lat;
      if (maxLat == null || lat > maxLat) maxLat = lat;
      if (minLng == null || lng < minLng) minLng = lng;
      if (maxLng == null || lng > maxLng) maxLng = lng;
    }

    if (minLat != null) {
      final bounds = LatLngBounds(
        LatLng(minLat!, minLng!),
        LatLng(maxLat!, maxLng!),
      );
      // bounds.isValid is not available in Recent flutter_map versions, assuming valid if points exist
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
    }
  }

  void _debouncedFetch() {
    if (_searchController.text.isNotEmpty) return;
    _fetchVisibleBranches();
  }

  Future<void> _determinePosition() async {
    final hasPermission = await _locationService.checkPermission(
      context: context,
    );
    if (!hasPermission) return;

    try {
      final lastPosition = await _locationService.getLastKnownPosition();
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

      final position = await _locationService.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        if (_isMapReady) {
          _mapController.move(_currentPosition!, 15);
        }
        _startLocationUpdates();
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _startLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _locationService.getPositionStream().listen((
      Position position,
    ) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      if (_isFollowingUser && _isMapReady) {
        _mapController.move(_currentPosition!, 17);
      }
    });
  }

  Future<void> _fetchVisibleBranches() async {
    if (!mounted || !_isMapReady) return;

    final bounds = _mapController.camera.visibleBounds;
    final zoom = _mapController.camera.zoom;
    final searchQuery = _searchController.text.trim();

    if (searchQuery.isNotEmpty) return;

    _mapManager.fetchVisibleBranches(
      bounds: bounds,
      zoom: zoom,
      searchQuery: searchQuery.isEmpty ? null : searchQuery,
    );
  }

  Future<void> _showNearbyBranches() async {
    if (_currentPosition == null) {
      await _determinePosition();
    }

    if (_currentPosition != null && _isMapReady) {
      _mapController.move(_currentPosition!, 15);
      _fetchVisibleBranches();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Поиск объектов рядом...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _openExternalMap(LatLng destination) async {
    final lat = destination.latitude;
    final lng = destination.longitude;
    final webUrl = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng",
    );

    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось открыть карту: $e')));
      }
    }
  }

  void _showBranchDetails(Branch branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => BranchDetailsSheet(
            branch: branch,
            onBuildRoute: () {
              final lat = branch.latitude;
              final lng = branch.longitude;
              if (lat != null && lng != null) {
                Navigator.pop(ctx);
                _openExternalMap(LatLng(lat, lng));
              }
            },
          ),
    );
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
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        _onSearchChanged();
                      },
                    )
                    : const Icon(Icons.search),
          ),
          onTap: () {
            setState(() {});
          },
          onChanged: (_) => setState(() {}),
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
            backgroundColor: _isFollowingUser ? Colors.blue : null,
            onPressed: () {
              setState(() => _isFollowingUser = true);
              if (_currentPosition != null) {
                if (_isMapReady) {
                  _mapController.move(_currentPosition!, 17);
                }
              } else {
                _determinePosition();
              }
            },
            child: Icon(
              Icons.my_location,
              color: _isFollowingUser ? Colors.white : null,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
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
                      _mapController.move(
                        LatLng(savedLat, savedLng),
                        savedZoom ?? 12,
                      );
                    } else if (_currentPosition != null) {
                      _mapController.move(_currentPosition!, 15);
                    }
                  } catch (_) {}
                }

                // Fetch initial data
                Future.delayed(
                  const Duration(milliseconds: 500),
                  _fetchVisibleBranches,
                );
              },
              initialCenter:
                  widget.initialLocation ?? const LatLng(42.8746, 74.5698),
              initialZoom: widget.initialLocation != null ? 16 : 12,
              maxZoom: 18.4,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_isFollowingUser) {
                    setState(() => _isFollowingUser = false);
                  }
                  _savePosition(camera);
                }
                _debouncedFetch();
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    Theme.of(context).brightness == Brightness.dark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.applearn',
              ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle:
                                (_currentHeading -
                                    _mapController.camera.rotation) *
                                (math.pi / 180),
                            child: CustomPaint(
                              size: const Size(120, 120),
                              painter: _BeamPainter(color: Colors.blueAccent),
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 5),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 80,
                  size: const Size(45, 45),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 18,
                  markers: _markers,
                  onMarkerTap: (marker) {
                    final branch = _markerBranchMap[marker.key];
                    if (branch != null) {
                      _showBranchDetails(branch);
                    }
                  },
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2B2E4A),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          _buildSearchPanel(),

          if (_mapManager.loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),

          if (_isListView)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child:
                  _mapManager.filteredBranches.isEmpty
                      ? const Center(child: Text('Магазины не найдены'))
                      : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _mapManager.filteredBranches.length,
                        itemBuilder: (context, index) {
                          final branch = _mapManager.filteredBranches[index];
                          final name = branch.company?.name ?? 'Магазин';
                          final logoUrl = branch.company?.logoUrl;
                          final category = branch.company?.category ?? 'Другое';
                          final discount = branch.company?.discountPercentage;

                          Color catColor = Colors.grey;
                          switch (category.toLowerCase()) {
                            case 'еда':
                              catColor = Colors.orange;
                              break;
                            case 'одежда':
                              catColor = Colors.purple;
                              break;
                            case 'электроника':
                              catColor = Colors.blueGrey;
                              break;
                            case 'услуги':
                              catColor = Colors.pink;
                              break;
                            case 'аптека':
                              catColor = Colors.teal;
                              break;
                          }

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                setState(() => _isListView = false);
                                final lat = branch.latitude;
                                final lng = branch.longitude;
                                if (lat != null && lng != null) {
                                  _mapController.move(LatLng(lat, lng), 16);
                                  _showBranchDetails(branch);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                        image:
                                            logoUrl != null
                                                ? DecorationImage(
                                                  image: NetworkImage(logoUrl),
                                                  fit: BoxFit.cover,
                                                )
                                                : null,
                                      ),
                                      child:
                                          logoUrl == null
                                              ? const Center(
                                                child: Icon(
                                                  Icons.store,
                                                  color: Colors.grey,
                                                ),
                                              )
                                              : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: catColor.withOpacity(
                                                    0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  category,
                                                  style: TextStyle(
                                                    color: catColor,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              if (discount != null &&
                                                  discount > 0) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '-$discount%',
                                                    style: const TextStyle(
                                                      color: Colors.green,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    if (!_searchFocusNode.hasFocus && _searchController.text.isNotEmpty)
      return const SizedBox();
    if (!_searchFocusNode.hasFocus) return const SizedBox();

    final categories = [
      {
        'name': 'Рядом',
        'icon': Icons.near_me,
        'term': '__nearby__',
        'color': Colors.blue,
      },
      {
        'name': 'Еда',
        'icon': Icons.restaurant,
        'term': 'Еда',
        'color': Colors.orange,
      },
      {
        'name': 'Одежда',
        'icon': Icons.checkroom,
        'term': 'Одежда',
        'color': Colors.purple,
      },
      {
        'name': 'Электроника',
        'icon': Icons.devices,
        'term': 'Электроника',
        'color': Colors.blueGrey,
      },
      {
        'name': 'Услуги',
        'icon': Icons.content_cut,
        'term': 'Услуги',
        'color': Colors.pink,
      },
      {
        'name': 'Другое',
        'icon': Icons.grid_view,
        'term': 'Другое',
        'color': Colors.grey,
      },
    ];

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Категории',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children:
                  categories.map((cat) {
                    return _buildCategoryItem(
                      cat['name'] as String,
                      cat['icon'] as IconData,
                      cat['term'] as String,
                      cat['color'] as Color,
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(
    String name,
    IconData icon,
    String searchTerm,
    Color color,
  ) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (searchTerm == '__nearby__') {
          _showNearbyBranches();
        } else {
          _searchController.text = searchTerm;
          _onSearchChanged();
        }
      },
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkerIcon(String? logoUrl, String name, int priority) {
    if (priority == 1) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.hardEdge,
                  child:
                      logoUrl != null
                          ? Image.network(logoUrl, fit: BoxFit.cover)
                          : const Icon(
                            Icons.star,
                            color: Colors.orange,
                            size: 20,
                          ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (priority == 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child:
                logoUrl != null
                    ? Container(
                      width: 28,
                      height: 28,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: Image.network(logoUrl, fit: BoxFit.cover),
                    )
                    : const Icon(
                      Icons.store,
                      color: Color(0xFF2B2E4A),
                      size: 20,
                    ),
          ),
          ClipPath(
            clipper: _TriangleClipper(),
            child: Container(width: 10, height: 6, color: Colors.white),
          ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4A90E2),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 3),
        ],
      ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BeamPainter extends CustomPainter {
  final Color color;
  _BeamPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint =
        Paint()
          ..shader = RadialGradient(
            colors: [color.withOpacity(0.4), color.withOpacity(0.0)],
            stops: const [0.2, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius));
    final path =
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: radius),
            -math.pi / 2 - (math.pi * 35 / 180),
            math.pi * 70 / 180,
            false,
          )
          ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

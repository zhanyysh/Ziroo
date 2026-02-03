import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart'; // Added Compass
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math; // Added for rotation calculations

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

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<CompassEvent>?
  _compassStreamSubscription; // Слушатель компаса
  bool _isFollowingUser = false;
  double _currentHeading = 0.0;
  
  // Кэшированные маркеры для оптимизации и стабильности кликов
  List<Marker> _markers = [];
  final Map<Key, Map<String, dynamic>> _markerBranchMap = {};

  @override
  void initState() {
    super.initState();
    _loadSavedPosition();
    _determinePosition();
    _startCompass(); // Запускаем компас отдельно
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _compassStreamSubscription?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _startCompass() {
    // Слушаем магнитный сенсор для ПЛАВНОГО и ТОЧНОГО поворота
    _compassStreamSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      final heading = event.heading;
      if (heading != null) {
        setState(() {
          // Если компас доступен, используем его (он точнее при покое)
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

  String _normalize(String text) {
    return text
        .replaceAll('kh', 'h')
        .replaceAll('ts', 'c')
        .replaceAll('zh', 'j')
        .replaceAll('yo', 'e');
  }

  void _updateMarkers() {
    final newMarkers = <Marker>[];
    _markerBranchMap.clear();

    debugPrint('Updating markers. Branches count: ${_filteredBranches.length}');

    for (var branch in _filteredBranches) {
      final lat = branch['latitude'] as double?;
      final lng = branch['longitude'] as double?;
      final company = branch['companies'] as Map<String, dynamic>?;
      final logoUrl = company?['logo_url'] as String?;
      final name = company?['name'] as String? ?? '';
      final priority = branch['map_priority'] as int? ?? 3;
      final id = branch['id'].toString();

      if (lat == null || lng == null) continue;

      // Используем уникальный ключ для каждого маркера
      final key = ValueKey(id);

      // ДИНАМИЧЕСКИЙ РАЗМЕР МАРКЕРА
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

      newMarkers.add(marker);
      _markerBranchMap[key] = branch;
    }
    
    _markers = newMarkers; 
    debugPrint('Markers updated. Count: ${_markers.length}');
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final text = _searchController.text.toLowerCase().trim();

      // Viewport Loading reset
      if (text.isEmpty) {
        _fetchVisibleBranches();
        return;
      }

      setState(() => _loading = true); // Corrected syntax

      try {
        List<Map<String, dynamic>> finalResults = [];

        // 1. Попытка поиска по полному запросу
        final results = List<Map<String, dynamic>>.from(await _rpcSearch(text));

        // 2. Если результатов мало и запрос состоит из нескольких слов (например "Globus Свердлова")
        // Пробуем Smart Search: ищем по первому слову ("Globus"), а потом фильтруем по остальным
        if (results.isEmpty && text.contains(' ')) {
          final words = text.split(' ');
          final firstWord = words.first; // "Globus"
          final otherWords = words.sublist(1).join(' ').trim(); // "Свердлова"

          if (firstWord.length > 2) {
            final broadResults = List<Map<String, dynamic>>.from(
              await _rpcSearch(firstWord),
            );

            // Фильтруем локально
            finalResults =
                broadResults.where((branch) {
                  final address =
                      (branch['address'] as String? ?? '').toLowerCase();
                  final name = (branch['name'] as String? ?? '').toLowerCase();
                  return address.contains(otherWords) ||
                      name.contains(otherWords);
                }).toList();

            // Если фильтр отсек все, возвращаем хотя бы широкий поиск (все Глобусы)
            if (finalResults.isEmpty) {
              finalResults = broadResults;
            }
          }
        } else {
          finalResults = results;
        }

        if (mounted) {
          setState(() {
            _branches = finalResults;
            _filteredBranches = finalResults;
            _loading = false;
          });

          // Логика перемещения камеры (Smart Camera)
          if (finalResults.isNotEmpty) {
            // Если результат ОДИН (например точное совпадение адреса) -> Зуммируем
            if (finalResults.length == 1) {
              final lat = finalResults[0]['latitude'] as double?;
              final lng = finalResults[0]['longitude'] as double?;
              if (lat != null && lng != null) {
                _mapController.move(LatLng(lat, lng), 17);
              }
            }
            // Если результатов МНОГО (например "Одежда")
            else {
              // Если это категория (много точек) -> не меняем зум радикально, просто вмещаем
              _fitCameraToResults(finalResults);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Найдено: ${finalResults.length}')),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Search error: $e');
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<List<dynamic>> _rpcSearch(String query) async {
    return await Supabase.instance.client.rpc(
      'search_branches',
      params: {
        'query_text': query,
        'user_lat': _currentPosition?.latitude,
        'user_lng': _currentPosition?.longitude,
      },
    );
  }

  void _fitCameraToResults(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return;

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

    if (minLat != null) {
      final bounds = LatLngBounds(
        LatLng(minLat!, minLng!),
        LatLng(maxLat!, maxLng!),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
    }
  }

  void _debouncedFetch() {
    // Включаем Viewport Loading даже при поиске
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
          builder:
              (ctx) => AlertDialog(
                title: const Text('Геолокация выключена'),
                content: const Text(
                  'Для определения местоположения включите геолокацию.',
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
        final openAppSettings = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Доступ к геолокации'),
                content: const Text(
                  'Доступ к геолокации заблокирован навсегда. Пожалуйста, разрешите доступ в настройках приложения, чтобы мы могли показать ваше местоположение.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Настройки'),
                  ),
                ],
              ),
        );

        if (openAppSettings == true) {
          await Geolocator.openAppSettings();
        }
      }
      return;
    }

    try {
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
        // Запускаем слушатель
        _startLocationUpdates();
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _startLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Обновляем каждые 5 метров
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        // _currentHeading = position.heading; // УБРАЛИ: GPS курс слишком дерганый и работает только в движении
      });

      // Режим слежения: камера двигается за юзером
      if (_isFollowingUser && _isMapReady) {
        _mapController.move(_currentPosition!, 17);
      }
    });
  }

  Future<void> _fetchVisibleBranches() async {
    if (!mounted || !_isMapReady) return;

    final bounds = _mapController.camera.visibleBounds;
    final zoom = _mapController.camera.zoom;

    // TWEAK: Увеличиваем "виртуальный" зум для базы данных
    // Проблема: Маленькие объекты исчезают слишком рано (на зуме 15).
    // Решение: Обманываем сервер, отправляя зум + 1.5.
    // Теперь маленькие объекты появятся уже на 13.5
    final adjustedZoom = zoom + 1.5;

    try {
      final data = await Supabase.instance.client.rpc(
        'get_branches_in_view',
        params: {
          'min_lat': bounds.south,
          'max_lat': bounds.north,
          'min_lng': bounds.west,
          'max_lng': bounds.east,
          'zoom_level': adjustedZoom,
        },
      );

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(data);
          final searchText = _searchController.text.trim().toLowerCase();

          if (searchText.isNotEmpty) {
            // ЛОКАЛЬНАЯ ФИЛЬТРАЦИЯ (Viewport Filtering)
            final words = searchText.split(' ');

            _filteredBranches =
                _branches.where((branch) {
                  final company = branch['companies'] as Map<String, dynamic>?;
                  final name =
                      (company?['name'] as String? ?? '').toLowerCase();
                  final branchName =
                      (branch['name'] as String? ?? '').toLowerCase();
                  final category =
                      (company?['category'] as String? ?? '').toLowerCase();
                  final desc =
                      (company?['description'] as String? ?? '').toLowerCase();
                  final address =
                      (branch['address'] as String? ?? '').toLowerCase();

                  final fullText = '$name $branchName $category $desc $address';

                  return words.every((w) => fullText.contains(w));
                }).toList();
          } else {
            _filteredBranches = _branches;
          }
          
          _updateMarkers(); // Обновляем маркеры
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
      // Explicitly load data because auto-fetch is disabled
      _fetchVisibleBranches();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Поиск объектов рядом...'),
          duration: Duration(seconds: 1),
        ),
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
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        // FocusScope.of(context).unfocus(); // Leave focus to show panel
                        setState(() {}); 
                        _onSearchChanged();
                      },
                    )
                    : const Icon(Icons.search),
          ),
          onTap: () {
             setState(() {}); // Show panel
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
                      _mapController.move(
                        LatLng(savedLat, savedLng),
                        savedZoom ?? 12,
                      );
                    } else if (_currentPosition != null) {
                      _mapController.move(_currentPosition!, 15);
                    }
                  } catch (_) {}
                }

                // Fetch initial data after camera move (with slight delay for bounds)
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
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
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
              // Слой местоположения пользователя (Не кластеризуется)
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 120, // Увеличили для "фонарика" (было 36)
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Слой 1: "Фонарик" (луч)
                          // Поворачиваем с учетом поворота карты
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
                          // Слой 2: Сама точка (маркер)
                          Container(
                            width: 24, // Еще компактнее (было 36)
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 5,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ), // Закрываем MarkerLayer
              
              // Слой маркеров магазинов (Кластеризация)
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 80,
                  size: const Size(45, 45),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 18,
                  markers: _markers, // Используем закэшированный список
                  // ВАЖНО: Используем нативный обработчик кликов плагина
                  onMarkerTap: (marker) {
                    final branch = _markerBranchMap[marker.key];
                    if (branch != null) {
                      _showBranchDetails(branch);
                    } else {
                      debugPrint('Branch not found for marker key: ${marker.key}');
                    }
                  },
                  builder: (context, markers) {
                    // КРАСИВЫЙ КЛАСТЕР
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2B2E4A),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // SEARCH PANEL (Categories)
          _buildSearchPanel(),

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
              child:
                  _filteredBranches.isEmpty
                      ? const Center(child: Text('Магазины не найдены'))
                      : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _filteredBranches.length,
                        itemBuilder: (context, index) {
                          final branch = _filteredBranches[index];
                          final company =
                              branch['companies'] as Map<String, dynamic>?;
                          final name = company?['name'] as String? ?? 'Магазин';
                          // final address = branch['name'] as String? ?? ''; // Address not main focus in card
                          final logoUrl = company?['logo_url'] as String?;
                          // final desc = company?['description'] as String? ?? '';
                          
                          // Новые поля (будут доступны после обновления SQL)
                          final category = company?['category'] as String? ?? 'Другое';
                          final discount = company?['discount_percentage'] as int?;

                          // Определяем цвет категории для UI
                          Color catColor;
                          switch(category.toLowerCase()) {
                            case 'еда': catColor = Colors.orange; break;
                            case 'одежда': catColor = Colors.purple; break;
                            case 'электроника': catColor = Colors.blueGrey; break;
                            case 'услуги': catColor = Colors.pink; break;
                            case 'аптека': catColor = Colors.teal; break;
                            default: catColor = Colors.grey;
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
                                  offset: const Offset(0, 4),
                                )
                              ],
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
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
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    // Логотип
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                        image: logoUrl != null 
                                          ? DecorationImage(
                                              image: NetworkImage(logoUrl), 
                                              fit: BoxFit.cover
                                            )
                                          : null,
                                      ),
                                      child: logoUrl == null 
                                        ? const Center(child: Icon(Icons.store, color: Colors.grey)) 
                                        : null,
                                    ),
                                    const SizedBox(width: 16),
                                    
                                    // Информация
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                              // Категория Чип
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: catColor.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  category,
                                                  style: TextStyle(
                                                    color: catColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              
                                              const SizedBox(width: 8),

                                              // Скидка Чип (если есть)
                                              if (discount != null && discount > 0)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    '-$discount%',
                                                    style: const TextStyle(
                                                      color: Colors.green,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          )
                                        ],
                                      ),
                                    ),

                                    // Стрелка
                                    const Icon(Icons.chevron_right, color: Colors.grey),
                                  ],
                                ),
                              ),
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
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.redAccent,
                      ),
                    ),
                  );
                },
              ),
            ),

          if (_searchController.text.isNotEmpty &&
              _searchFocusNode.hasFocus &&
              !_isListView)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child:
                  _filteredBranches.isEmpty
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
                              backgroundImage:
                                  logoUrl != null
                                      ? NetworkImage(logoUrl)
                                      : null,
                              child:
                                  logoUrl == null
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

  Widget _buildMarkerIcon(String? logoUrl, String name, int priority) {
    // -------------------------------------------------------------------------
    // СТИЛЬ 1: "SMART CHIP" (Для VIP/Крупных)
    // Выглядит как пилюля с логотипом и названием.
    // -------------------------------------------------------------------------
    if (priority == 1) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Основное тело "Чипса"
          Container(
            height: 40,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
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
                // Логотип слева
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    // Убрали DecorationImage, используем child
                  ),
                  clipBehavior: Clip.hardEdge, // Обрезаем контент по кругу
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
                // Название
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // -------------------------------------------------------------------------
    // СТИЛЬ 2: "FLOATING PIN" (Для средних магазинов)
    // Аккуратный белый кружок с иконкой.
    // -------------------------------------------------------------------------
    if (priority == 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
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
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Image.network(logoUrl, fit: BoxFit.cover),
                    )
                    : const Icon(
                      Icons.store_mall_directory,
                      color: Color(0xFF2B2E4A),
                      size: 20,
                    ),
          ),
          // Ножка пина (треугольник вниз)
          ClipPath(
            clipper: _TriangleClipper(),
            child: Container(width: 10, height: 6, color: Colors.white),
          ),
        ],
      );
    }

    // -------------------------------------------------------------------------
    // СТИЛЬ 3: "SOFT DOT" (Мелкие точки)
    // -------------------------------------------------------------------------
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4A90E2), // Приятный голубой цвет
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Center(
        child: SizedBox(), // Пустой центр, просто цветная точка
      ),
    );
  }

  Future<void> _openExternalMap(LatLng destination) async {
    final lat = destination.latitude;
    final lng = destination.longitude;

    final dgisUrl = Uri.parse(
      "dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat",
    );
    final googleMapsUrl = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    final geoUrl = Uri.parse(
      "geo:$lat,$lng?q=$lat,$lng",
    ); // Universal geo scheme
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

  void _showBranchDetails(Map<String, dynamic> branch) {
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

  Widget _buildSearchPanel() {
    if (!_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) return const SizedBox();
    if (!_searchFocusNode.hasFocus) return const SizedBox();

    final categories = [
      {'name': 'Рядом', 'icon': Icons.near_me, 'term': '__nearby__', 'color': Colors.blue},
      {'name': 'Еда', 'icon': Icons.restaurant, 'term': 'Еда', 'color': Colors.orange},
      {'name': 'Одежда', 'icon': Icons.checkroom, 'term': 'Одежда', 'color': Colors.purple},
      {'name': 'Электроника', 'icon': Icons.devices, 'term': 'Электроника', 'color': Colors.blueGrey},
      {'name': 'Услуги', 'icon': Icons.content_cut, 'term': 'Услуги', 'color': Colors.pink},
      {'name': 'Развлечения', 'icon': Icons.theater_comedy, 'term': 'Развлечения', 'color': Colors.redAccent},
      {'name': 'Другое', 'icon': Icons.grid_view, 'term': 'Другое', 'color': Colors.grey},
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
              children: categories.map((cat) {
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

  Widget _buildCategoryItem(String name, IconData icon, String searchTerm, Color color) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus(); // Скрываем панель и клавиатуру
        
        if (searchTerm == '__nearby__') {
          _showNearbyBranches(); // Логика "Рядом"
        } else {
          _searchController.text = searchTerm;
          _onSearchChanged(); // Обычный поиск
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[800] 
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Простой клиппер для треугольника (ножки пина)
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



// Рисует "луч" (сектор) для геолокации
class _BeamPainter extends CustomPainter {
  final Color color;

  _BeamPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Градиент от центра к краю (синий -> прозрачный)
    final paint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withOpacity(0.4), // Полупрозрачный у основания
              color.withOpacity(0.0), // Прозрачный на конце
            ],
            stops: const [0.2, 1.0], // Начинает исчезать сразу
          ).createShader(Rect.fromCircle(center: center, radius: radius));

    // Рисуем сектор (Arc) направленный ВВЕРХ (-pi/2)
    // Ширина сектора: 70 градусов (примерно)
    final path =
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: radius),
            -math.pi / 2 - (math.pi * 35 / 180), // -90 - 35
            math.pi * 70 / 180, // 70 градусов ширина
            false,
          )
          ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async';
import '../../models/branch.dart';
import '../../repositories/branch_repository.dart';

class MapManager extends ChangeNotifier {
  final BranchRepository _repository = BranchRepository(
    Supabase.instance.client,
  );

  List<Branch> branches = [];
  List<Branch> filteredBranches = [];
  bool loading = false;
  Timer? _debounce;

  /// Загрузка объектов в видимой области (Viewport fetching)
  Future<void> fetchVisibleBranches({
    required LatLngBounds bounds,
    required double zoom,
    String? searchQuery,
  }) async {
    // Дебаунс, если запрос частый (например при скролле)
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      loading = true;
      notifyListeners();

      // TWEAK: Увеличиваем "виртуальный" зум для базы данных
      final adjustedZoom = zoom + 1.5;

      try {
        branches = await _repository.getBranchesInView(
          minLat: bounds.south,
          maxLat: bounds.north,
          minLng: bounds.west,
          maxLng: bounds.east,
          zoomLevel: adjustedZoom,
        );

        // Применяем локальную фильтрацию, если есть поисковый запрос
        _applyLocalFilter(searchQuery);
      } catch (e) {
        debugPrint('Error fetching viewport branches: $e');
      } finally {
        loading = false;
        notifyListeners();
      }
    });
  }

  /// Поиск через RPC (Smart Search Logic)
  Future<void> searchBranches(
    String query, {
    double? userLat,
    double? userLng,
  }) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.isEmpty) {
        // Если поиск очистили - ничего не делаем, UI сам решит вызвать fetchVisible
        return;
      }

      loading = true;
      notifyListeners();

      try {
        List<Branch> finalResults = [];

        // 1. RPC поиск
        final resultsList = await _repository.searchBranches(
          query: query,
          userLat: userLat,
          userLng: userLng,
        );

        // 2. Smart Search Logic (если RPC вернул мало, а запрос сложный)
        if (resultsList.isEmpty && query.contains(' ')) {
          final words = query.split(' ');
          final firstWord = words.first;
          final otherWords = words.sublist(1).join(' ').trim();

          if (firstWord.length > 2) {
            final broadResults = await _repository.searchBranches(
              query: firstWord,
              userLat: userLat,
              userLng: userLng,
            );

            // Локальная фильтрация
            finalResults =
                broadResults.where((branch) {
                  final address = (branch.address ?? '').toLowerCase();
                  final name = (branch.name ?? '').toLowerCase();
                  return address.contains(otherWords) ||
                      name.contains(otherWords);
                }).toList();

            if (finalResults.isEmpty) {
              finalResults = broadResults; // Fallback
            }
          }
        } else {
          finalResults = resultsList;
        }

        branches = finalResults;
        filteredBranches =
            finalResults; // В режиме поиска показываем только результаты
      } catch (e) {
        debugPrint('Search error: $e');
      } finally {
        loading = false;
        notifyListeners();
      }
    });
  }

  void _applyLocalFilter(String? searchQuery) {
    if (searchQuery == null || searchQuery.isEmpty) {
      filteredBranches = List.from(branches);
      return;
    }

    final words = searchQuery.toLowerCase().split(' ');
    filteredBranches =
        branches.where((branch) {
          final name = (branch.company?.name ?? '').toLowerCase();
          final branchName = (branch.name ?? '').toLowerCase();
          final category = (branch.company?.category ?? '').toLowerCase();
          final desc = (branch.company?.description ?? '').toLowerCase();
          final address = (branch.address ?? '').toLowerCase();

          final fullText = '$name $branchName $category $desc $address';
          return words.every((w) => fullText.contains(w));
        }).toList();
  }

  void disposeManager() {
    _debounce?.cancel();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/branch.dart';

class BranchRepository {
  final SupabaseClient _client;

  BranchRepository(this._client);

  /// Получает список филиалов в видимой области карты
  Future<List<Branch>> getBranchesInView({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double zoomLevel,
  }) async {
    final response = await _client.rpc(
      'get_branches_in_view',
      params: {
        'min_lat': minLat,
        'max_lat': maxLat,
        'min_lng': minLng,
        'max_lng': maxLng,
        'zoom_level': zoomLevel,
      },
    );

    final data = List<Map<String, dynamic>>.from(response);
    return data.map((e) => Branch.fromJson(e)).toList();
  }

  /// Поиск филиалов по текстовому запросу
  Future<List<Branch>> searchBranches({
    required String query,
    double? userLat,
    double? userLng,
  }) async {
    final response = await _client.rpc(
      'search_branches',
      params: {'query_text': query, 'user_lat': userLat, 'user_lng': userLng},
    );

    final data = List<Map<String, dynamic>>.from(response);
    return data.map((e) => Branch.fromJson(e)).toList();
  }
}

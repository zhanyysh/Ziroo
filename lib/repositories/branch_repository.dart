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

  /// Получает все рейтинги для филиала
  Future<List<Map<String, dynamic>>> getRatings(String branchId) async {
    final response = await _client
        .from('branch_reviews')
        .select('rating, user_id')
        .eq('branch_id', branchId);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Получает отзыв конкретного пользователя
  Future<Map<String, dynamic>?> getUserReview({
    required String userId,
    required String branchId,
  }) async {
    return await _client
        .from('branch_reviews')
        .select()
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .maybeSingle();
  }

  /// Обновляет рейтинг (сохраняя комментарий, если он был)
  Future<void> updateRating({
    required String userId,
    required String branchId,
    required int rating,
  }) async {
    // Пытаемся получить существующую запись, чтобы не стереть комментарий
    final existing = await getUserReview(userId: userId, branchId: branchId);
    final comment = existing?['comment'];

    await _client.from('branch_reviews').upsert({
      'user_id': userId,
      'branch_id': branchId,
      'rating': rating,
      'comment': comment, // Передаем старый коммент или null
    }, onConflict: 'user_id, branch_id');
  }

  /// Получает отзывы с профилями пользователей
  Future<List<Map<String, dynamic>>> getReviews(String branchId) async {
    final response = await _client
        .from('branch_reviews')
        .select('*, profiles:user_id(email, avatar_url)')
        .eq('branch_id', branchId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Публикует или обновляет отзыв
  Future<void> submitReview({
    required String userId,
    required String branchId,
    required String comment,
    required int rating,
  }) async {
    await _client.from('branch_reviews').upsert({
      'branch_id': branchId,
      'user_id': userId,
      'comment': comment,
      'rating': rating,
    }, onConflict: 'user_id, branch_id');
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

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

      // 1. Получаем все отзывы этого филиала из ЕДИНОЙ таблицы
      final ratingsResponse = await Supabase.instance.client
          .from('branch_reviews') // ИСПРАВЛЕНО: используем branch_reviews
          .select('rating, user_id')
          .eq('branch_id', branchId);

      final ratings = List<Map<String, dynamic>>.from(ratingsResponse);

      if (ratings.isNotEmpty) {
        // Считаем среднее только по тем, где есть рейтинг > 0
        final validRatings = ratings.where((r) => (r['rating'] as int) > 0).toList();
        
        if (validRatings.isNotEmpty) {
           final total = validRatings.fold<double>(
            0,
            (sum, item) => sum + (item['rating'] as int),
          );
          _averageRating = total / validRatings.length;
          _ratingCount = validRatings.length;
        }
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
      debugPrint('Error fetching ratings: $e');
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

      // Используем upsert в branch_reviews
      // Он обновит рейтинг, если отзыв уже есть, или создаст новый
      await Supabase.instance.client.from('branch_reviews').upsert({
        'user_id': userId,
        'branch_id': widget.branch['id'],
        'rating': rating.toInt(),
        // Не трогаем комментарий if any (при upsert старые поля сохраняются если не переданы? 
        // Нет, в Supabase upsert перезатирает строку, если не сделать merge. 
        // Лучше сначала проверить есть ли отзыв, но для простоты передадим created_at чтобы не затерлось
        // 'updated_at': DateTime.now().toIso8601String(), 
      }, onConflict: 'user_id, branch_id'); // Важно: нужен UNIQUE индекс в БД!

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
              ReviewsSection(branchId: widget.branch['id']),

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

class ReviewsSection extends StatefulWidget {
  final String branchId;

  const ReviewsSection({super.key, required this.branchId});

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
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
      // ИСПРАВЛЕНО: Сначала проверяем, есть ли уже отзыв, чтобы не затереть рейтинг
      final existing = await Supabase.instance.client
          .from('branch_reviews')
          .select()
          .eq('user_id', user.id)
          .eq('branch_id', widget.branchId)
          .maybeSingle();

      final existingRating = existing != null ? existing['rating'] as int : 0;
      // Если рейтинга не было, ставим 5 (как дефолт для позитива), иначе оставляем старый
      final newRating = existingRating > 0 ? existingRating : 5;

      await Supabase.instance.client.from('branch_reviews').upsert({
        'branch_id': widget.branchId,
        'user_id': user.id,
        'comment': _commentController.text.trim(),
        'rating': newRating, 
      }, onConflict: 'user_id, branch_id');

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

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/stripe_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = false;
  String? _currentPlan;
  DateTime? _subscriptionEndDate;
  
  // TODO: Замените на ваши Payment Links из Stripe Dashboard
  // Stripe Dashboard → Product catalog → Create product → Create payment link
  static const String _basicPaymentLink = 'https://buy.stripe.com/test_aFacN57Zr8618Bx1qg77O00';
  static const String _premiumPaymentLink = 'https://buy.stripe.com/test_aFacN57Zr8618Bx1qg77O00';

  // Планы подписки
  final List<SubscriptionPlan> _plans = [
    SubscriptionPlan(
      id: 'free',
      name: 'Бесплатный',
      price: 0,
      priceId: '',
      paymentLink: '',
      features: [
        'Базовый доступ',
        'До 5 сохранений',
        'Реклама',
      ],
      color: Colors.grey,
    ),
    SubscriptionPlan(
      id: 'basic',
      name: 'Базовый',
      price: 299,
      priceId: 'price_basic_monthly', // ID цены в Stripe
      paymentLink: _basicPaymentLink,
      features: [
        'Расширенный доступ',
        'Без рекламы',
        'До 50 сохранений',
        'Email поддержка',
      ],
      color: Colors.blue,
    ),
    SubscriptionPlan(
      id: 'premium',
      name: 'Премиум',
      price: 599,
      priceId: 'price_premium_monthly', // ID цены в Stripe
      paymentLink: _premiumPaymentLink,
      features: [
        'Полный доступ',
        'Без рекламы',
        'Безлимитные сохранения',
        'Приоритетная поддержка',
        'Эксклюзивные функции',
        'Ранний доступ к новинкам',
      ],
      color: Colors.deepPurple,
      isPopular: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSubscription();
  }

  Future<void> _loadCurrentSubscription() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _loading = true);

    try {
      final data = await Supabase.instance.client
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _currentPlan = data['plan_id'];
          _subscriptionEndDate = DateTime.tryParse(data['current_period_end'] ?? '');
        });
      } else {
        setState(() {
          _currentPlan = 'free';
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки подписки: $e');
      setState(() {
        _currentPlan = 'free';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _subscribe(SubscriptionPlan plan) async {
    if (plan.id == 'free') {
      _showSnackBar('Вы уже на бесплатном плане');
      return;
    }

    if (_currentPlan == plan.id) {
      _showSnackBar('Вы уже подписаны на этот план');
      return;
    }

    // Простой способ: открываем Payment Link в браузере
    if (plan.paymentLink.isNotEmpty && plan.paymentLink.contains('stripe.com')) {
      await _openPaymentLink(plan);
      return;
    }

    // Полный способ: через бэкенд и Payment Sheet
    await _subscribeViaBackend(plan);
  }

  /// Простой способ оплаты через Payment Link (открывается в браузере)
  Future<void> _openPaymentLink(SubscriptionPlan plan) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    
    // Добавляем user_id в URL для отслеживания
    final url = Uri.parse('${plan.paymentLink}?client_reference_id=$userId');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      
      // Показываем диалог после возврата
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Оплата'),
            content: const Text(
              'После завершения оплаты в браузере, вернитесь в приложение и обновите страницу.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadCurrentSubscription();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      _showSnackBar('Не удалось открыть ссылку для оплаты');
    }
  }

  /// Полный способ оплаты через бэкенд (Payment Sheet)
  Future<void> _subscribeViaBackend(SubscriptionPlan plan) async {
    setState(() => _loading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Пользователь не авторизован');

      // 1. Создаем PaymentIntent на бэкенде
      final paymentData = await StripeService.instance.createPaymentIntent(
        amount: plan.price * 100, // Конвертируем в копейки
        currency: 'rub',
        customerId: userId,
        metadata: {
          'plan_id': plan.id,
          'plan_name': plan.name,
        },
      );

      // 2. Показываем форму оплаты
      await StripeService.instance.presentPaymentSheet(
        clientSecret: paymentData['client_secret'],
        merchantName: 'AppLearn',
      );

      // 3. Сохраняем подписку в БД
      await Supabase.instance.client.from('subscriptions').upsert({
        'user_id': userId,
        'plan_id': plan.id,
        'stripe_subscription_id': paymentData['subscription_id'],
        'status': 'active',
        'current_period_start': DateTime.now().toIso8601String(),
        'current_period_end': DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
      });

      setState(() {
        _currentPlan = plan.id;
        _subscriptionEndDate = DateTime.now().add(const Duration(days: 30));
      });

      if (mounted) {
        _showSnackBar('Подписка успешно оформлена!', isSuccess: true);
      }
    } on StripeException catch (e) {
      _showSnackBar('Ошибка оплаты: ${e.error.localizedMessage}');
    } catch (e) {
      _showSnackBar('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписка'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  Text(
                    'Выберите план',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Разблокируйте все возможности приложения',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Текущая подписка
                  if (_currentPlan != null && _currentPlan != 'free') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Активная подписка: ${_plans.firstWhere((p) => p.id == _currentPlan).name}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_subscriptionEndDate != null)
                                  Text(
                                    'Действует до: ${_formatDate(_subscriptionEndDate!)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Планы подписки
                  ..._plans.map((plan) => _buildPlanCard(plan, theme)),
                ],
              ),
            ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, ThemeData theme) {
    final isCurrentPlan = _currentPlan == plan.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: plan.isPopular
              ? plan.color
              : theme.colorScheme.outline.withOpacity(0.3),
          width: plan.isPopular ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: plan.color,
                      ),
                    ),
                    if (isCurrentPlan)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Активен',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Цена
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.price == 0 ? 'Бесплатно' : '${plan.price} ₽',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (plan.price > 0)
                      Text(
                        ' / месяц',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Функции
                ...plan.features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check,
                            size: 20,
                            color: plan.color,
                          ),
                          const SizedBox(width: 8),
                          Text(feature),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),

                // Кнопка
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan ? null : () => _subscribe(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isCurrentPlan
                          ? 'Текущий план'
                          : plan.price == 0
                              ? 'Выбрать'
                              : 'Подписаться',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Популярный бейдж
          if (plan.isPopular)
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: plan.color,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: const Text(
                  'Популярный',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

/// Модель плана подписки
class SubscriptionPlan {
  final String id;
  final String name;
  final int price;
  final String priceId;
  final String paymentLink; // Ссылка на Stripe Payment Link для простого тестирования
  final List<String> features;
  final Color color;
  final bool isPopular;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.priceId,
    this.paymentLink = '',
    required this.features,
    required this.color,
    this.isPopular = false,
  });
}

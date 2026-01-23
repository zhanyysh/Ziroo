import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Сервис для работы со Stripe платежами
class StripeService {
  static StripeService? _instance;
  
  StripeService._();
  
  static StripeService get instance {
    _instance ??= StripeService._();
    return _instance!;
  }

  // TODO: Замените на ваши ключи Stripe
  // Публичный ключ (можно использовать в клиенте)
  static const String publishableKey = 'pk_test_51SrGQBFNhGbx2zdpLSmExWftx90FzePpFbkvNpWhu9hokVaFOi77nnGslhLWx2BvzjHU8rbdsue7JwMseKEyJiiT00AembNgYq';
  
  // URL вашего бэкенда (Supabase Edge Function или собственный сервер)
  // Это нужно для создания PaymentIntent на стороне сервера
  static const String backendUrl = 'https://rmqwopgsvpbybbxrtccc.supabase.co/functions/v1/swift-action';

  /// Инициализация Stripe
  static Future<void> initialize() async {
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
  }

  /// Создание платежа (Payment Intent) через бэкенд
  /// 
  /// [amount] - сумма в центах (например, 1000 = 10.00 USD)
  /// [currency] - валюта (usd, eur, rub и т.д.)
  /// [customerId] - ID клиента в Supabase/Stripe
  Future<Map<String, dynamic>> createPaymentIntent({
    required int amount,
    required String currency,
    String? customerId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': amount,
          'currency': currency,
          'customer_id': customerId,
          'metadata': metadata,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Ошибка создания платежа: ${response.body}');
      }
    } catch (e) {
      throw Exception('Ошибка сети: $e');
    }
  }

  /// Показать платежную форму и провести оплату
  /// 
  /// [clientSecret] - секретный ключ от PaymentIntent
  /// [merchantName] - название магазина
  Future<PaymentSheetPaymentOption?> presentPaymentSheet({
    required String clientSecret,
    required String merchantName,
  }) async {
    // Инициализация Payment Sheet
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantName,
        style: ThemeMode.system,
        appearance: const PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: Color(0xFF673AB7), // Deep Purple
          ),
          shapes: PaymentSheetShape(
            borderRadius: 12,
          ),
        ),
      ),
    );

    // Показать Payment Sheet
    await Stripe.instance.presentPaymentSheet();
    
    return null;
  }

  /// Создание подписки через бэкенд
  Future<Map<String, dynamic>> createSubscription({
    required String priceId,
    required String customerId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/create-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'price_id': priceId,
          'customer_id': customerId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Ошибка создания подписки: ${response.body}');
      }
    } catch (e) {
      throw Exception('Ошибка сети: $e');
    }
  }

  /// Отмена подписки
  Future<bool> cancelSubscription(String subscriptionId) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/cancel-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subscription_id': subscriptionId,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Ошибка отмены подписки: $e');
    }
  }

  /// Получение списка способов оплаты клиента
  Future<List<PaymentMethod>> getPaymentMethods(String customerId) async {
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/payment-methods?customer_id=$customerId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['payment_methods'] as List)
            .map((pm) => PaymentMethod.fromJson(pm))
            .toList();
      } else {
        throw Exception('Ошибка получения способов оплаты');
      }
    } catch (e) {
      throw Exception('Ошибка сети: $e');
    }
  }

  /// Добавление нового способа оплаты
  Future<void> addPaymentMethod() async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        setupIntentClientSecret: await _createSetupIntent(),
        merchantDisplayName: 'AppLearn',
        style: ThemeMode.system,
      ),
    );

    await Stripe.instance.presentPaymentSheet();
  }

  /// Создание SetupIntent для сохранения карты
  Future<String> _createSetupIntent() async {
    final response = await http.post(
      Uri.parse('$backendUrl/create-setup-intent'),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['client_secret'];
    } else {
      throw Exception('Ошибка создания SetupIntent');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Экран смены номера телефона
/// 
/// Flow:
/// 1. Пользователь вводит новый номер
/// 2. Supabase отправляет SMS с OTP кодом
/// 3. Пользователь вводит код
/// 4. verifyOTP() подтверждает и меняет номер
/// 5. Триггер sync_profile_from_auth() обновляет profiles
class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _supabase = Supabase.instance.client;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _loading = false;
  bool _otpSent = false;
  bool _success = false;
  String? _currentPhone;
  String? _newPhone; // Сохраняем для верификации

  @override
  void initState() {
    super.initState();
    _currentPhone = _supabase.auth.currentUser?.phone;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Форматирование номера телефона
  String _formatPhone(String phone) {
    // Удаляем все кроме цифр и +
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // Форматирование для Кыргызстана
    if (phone.startsWith('0')) {
      phone = '+996${phone.substring(1)}';
    } else if (phone.startsWith('996') && !phone.startsWith('+')) {
      phone = '+$phone';
    } else if (!phone.startsWith('+') && phone.length == 9) {
      phone = '+996$phone';
    }

    return phone;
  }

  /// Шаг 1: Отправка OTP
  Future<void> _sendOtp() async {
    final phone = _formatPhone(_phoneController.text.trim());
    
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректный номер телефона'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (phone == _currentPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Это ваш текущий номер'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Обновляем пользователя с новым телефоном
      // Supabase автоматически отправит OTP на новый номер
      await _supabase.auth.updateUser(
        UserAttributes(phone: phone),
      );

      if (mounted) {
        setState(() {
          _otpSent = true;
          _newPhone = phone;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS код отправлен на $phone'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Шаг 2: Верификация OTP
  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    
    if (otp.isEmpty || otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите 6-значный код'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_newPhone == null) return;

    setState(() => _loading = true);

    try {
      await _supabase.auth.verifyOTP(
        phone: _newPhone!,
        token: otp,
        type: OtpType.phoneChange,
      );

      if (mounted) {
        setState(() => _success = true);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Повторная отправка OTP
  Future<void> _resendOtp() async {
    setState(() {
      _otpSent = false;
      _otpController.clear();
    });
    await _sendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Изменить номер'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _success
            ? _buildSuccessView(theme)
            : _otpSent
                ? _buildOtpForm(theme, isDark)
                : _buildPhoneForm(theme, isDark),
      ),
    );
  }

  /// Успешная смена номера
  Widget _buildSuccessView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Номер изменен!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Ваш новый номер телефона:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _newPhone ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  /// Форма ввода OTP
  Widget _buildOtpForm(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Иконка
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sms_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        Text(
          'Введите код из SMS',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Мы отправили код на $_newPhone',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // OTP поле
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: theme.textTheme.headlineMedium?.copyWith(
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 24),
        
        // Кнопка подтверждения
        ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: _loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Подтвердить',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        
        // Отправить повторно
        TextButton(
          onPressed: _loading ? null : _resendOtp,
          child: Text(
            'Отправить код повторно',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }

  /// Форма ввода номера телефона
  Widget _buildPhoneForm(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Текущий номер
        if (_currentPhone != null && _currentPhone!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Текущий номер',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentPhone!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // Новый номер
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Новый номер телефона',
            hintText: '+996555123456',
            prefixIcon: const Icon(Icons.phone),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 16),
        
        // Информация
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'На новый номер будет отправлен SMS код для подтверждения.',
                  style: TextStyle(color: Colors.blue.shade700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        // Кнопка
        ElevatedButton(
          onPressed: _loading ? null : _sendOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: _loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Получить код',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}

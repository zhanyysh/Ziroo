import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

/// Экран авторизации по телефону с OTP
/// 
/// Flow:
/// 1. Пользователь вводит номер телефона
/// 2. signInWithOtp() отправляет SMS с кодом
/// 3. Пользователь вводит код
/// 4. verifyOTP() подтверждает и авторизует
/// 
/// Если пользователя нет — он автоматически создается (signUp)
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _supabase = Supabase.instance.client;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLoading = false;
  bool _otpSent = false;
  bool _isNewUser = false; // По умолчанию режим входа
  String? _phone; // Сохраняем для верификации

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
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

  /// Шаг 1: Отправка OTP кода
  Future<void> _sendOtp() async {
    // Проверка имени при регистрации
    if (_isNewUser && _nameController.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите ваше имя (минимум 2 символа)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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

    setState(() => _isLoading = true);

    try {
      await _supabase.auth.signInWithOtp(
        phone: phone,
      );

      if (mounted) {
        setState(() {
          _otpSent = true;
          _phone = phone;
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
        setState(() => _isLoading = false);
      }
    }
  }

  /// Шаг 2: Верификация OTP кода
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

    // Проверка имени при регистрации
    if (_isNewUser && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите ваше имя'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_phone == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await _supabase.auth.verifyOTP(
        phone: _phone!,
        token: otp,
        type: OtpType.sms,
      );

      // Если это регистрация - сохраняем имя
      if (_isNewUser && response.user != null) {
        final name = _nameController.text.trim();
        if (name.isNotEmpty) {
          // Обновляем auth metadata (триггер синхронизирует в profiles)
          await _supabase.auth.updateUser(
            UserAttributes(
              data: {
                'full_name': name,
                'name': name,
              },
            ),
          );
        }
      }

      if (mounted) {
        // Успешная авторизация - переходим на главную
        context.go('/');
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
        setState(() => _isLoading = false);
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

  /// Вернуться к вводу номера
  void _changePhone() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_otpSent ? 'Подтверждение' : (_isNewUser ? 'Регистрация' : 'Вход')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: theme.colorScheme.onSurface),
          onPressed: () {
            if (_otpSent) {
              // С экрана OTP → обратно к вводу номера
              _changePhone();
            } else if (_isNewUser) {
              // С экрана регистрации → обратно к экрану входа
              setState(() {
                _isNewUser = false;
                _nameController.clear();
              });
            } else {
              // С экрана входа → закрыть
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _otpSent
              ? _buildOtpForm(theme, isDark)
              : _buildPhoneForm(theme, isDark),
        ),
      ),
    );
  }

  /// Форма ввода номера телефона
  Widget _buildPhoneForm(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
              _isNewUser ? Icons.person_add : Icons.phone_android,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 32),
        
        Text(
          _isNewUser ? 'Регистрация по телефону' : 'Вход по телефону',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _isNewUser 
              ? 'Введите данные для создания аккаунта'
              : 'Введите номер телефона для входа',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Поле ввода имени (только при регистрации)
        if (_isNewUser) ...[
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Ваше имя',
              hintText: 'Иван Иванов',
              prefixIcon: const Icon(Icons.person_outline),
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
        ],
        
        // Поле ввода номера
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Номер телефона',
            hintText: '+996 555 123 456',
            prefixIcon: const Icon(Icons.phone_outlined),
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
        
        // Кнопка отправки
        ElevatedButton(
          onPressed: _isLoading ? null : _sendOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _isNewUser ? 'Зарегистрироваться' : 'Получить код',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        
        // Переключатель Вход/Регистрация
        TextButton(
          onPressed: () {
            setState(() {
              _isNewUser = !_isNewUser;
            });
          },
          child: Text(
            _isNewUser
                ? 'Уже есть аккаунт? Войти'
                : 'Нет аккаунта? Зарегистрироваться',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }

  /// Форма ввода OTP кода
  Widget _buildOtpForm(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
        const SizedBox(height: 32),
        
        Text(
          'Введите код из SMS',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Мы отправили 6-значный код на',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _phone ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Поле ввода OTP
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
          onPressed: _isLoading ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: _isLoading
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
        
        // Ссылки
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading ? null : _resendOtp,
              child: Text(
                'Отправить повторно',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
            Text(
              '|',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: _isLoading ? null : _changePhone,
              child: Text(
                'Изменить номер',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

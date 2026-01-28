import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'phone_auth_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  Future<void> _signup() async {
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароли не совпадают'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) {
        Navigator.pop(
          context,
        ); // Pop back to auth handler (it will show Home if logged in)
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка регистрации: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nativeGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
      final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';
      final scopes = ['email', 'profile'];
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: webClientId,
        clientId: iosClientId,
      );
      final googleUser = await googleSignIn.attemptLightweightAuthentication();

      if (googleUser == null) {
        return;
      }

      // If we are in signup screen, we might want to pop first or handle it.
      // But usually google sign in is "login or register".
      // If we pop here, the AuthWrapper in the background will catch the session change.
      if (mounted) Navigator.pop(context);

      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
          await googleUser.authorizationClient.authorizeScopes(scopes);
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw const AuthException('No ID Token found.');
      }
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка входа через Google: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // If we popped, this might not be needed, but safe to keep
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Создать аккаунт',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Заполните данные для регистрации',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Email Field
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'example@mail.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor:
                      isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 16),

              // Password Field
              TextField(
                controller: _password,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor:
                      isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 16),

              // Confirm Password Field
              TextField(
                controller: _confirmPassword,
                obscureText: !_isConfirmPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Повторите пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor:
                      isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),

              // Signup Button
              ElevatedButton(
                onPressed: _loading ? null : _signup,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 2,
                  shadowColor: theme.colorScheme.primary.withOpacity(0.5),
                ),
                child:
                    _loading
                        ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                        : const Text(
                          'Зарегистрироваться',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
              const SizedBox(height: 16),

              // Google Sign In Button
              OutlinedButton.icon(
                onPressed: _loading ? null : _nativeGoogleSignIn,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: theme.colorScheme.outline),
                ),
                icon: SvgPicture.asset(
                  'assets/images/g-logo.svg',
                  height: 24,
                  width: 24,
                ),
                label: Text(
                  'Войти через Google',
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Phone Sign Up Button
              OutlinedButton.icon(
                onPressed: _loading ? null : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PhoneAuthScreen(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: theme.colorScheme.outline),
                ),
                icon: Icon(
                  Icons.phone_android,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                label: Text(
                  'Регистрация по телефону',
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
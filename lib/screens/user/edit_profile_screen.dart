import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _isGoogleUser = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      String name = user.userMetadata?['name'] ?? '';
      
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        
        if (data != null && data['full_name'] != null) {
          name = data['full_name'];
        }
      } catch (e) {
        // Ignore error, use metadata name
      }

      if (mounted) {
        setState(() {
          _nameController.text = name;
          _emailController.text = user.email ?? '';
          _isGoogleUser = user.appMetadata['provider'] == 'google';
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final newName = _nameController.text.trim();
      final newEmail = _emailController.text.trim();

      // 1. Обновляем Auth User (metadata и email)
      final updates = UserAttributes(
        email: (newEmail != user.email && !_isGoogleUser) ? newEmail : null,
        data: {'name': newName},
      );

      await Supabase.instance.client.auth.updateUser(updates);

      // 2. Обновляем таблицу profiles
      final profileUpdates = <String, dynamic>{
        'full_name': newName,
      };
      
      if (newEmail != user.email && !_isGoogleUser) {
        profileUpdates['email'] = newEmail;
      }

      await Supabase.instance.client
          .from('profiles')
          .update(profileUpdates)
          .eq('id', user.id);

      // 3. Показываем результат
      if (newEmail != user.email && !_isGoogleUser) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email обновлен. Пожалуйста, подтвердите новый email.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Профиль успешно обновлен'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Возвращаем true, чтобы обновить родительский экран
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
            content: Text('Ошибка обновления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование профиля'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Личные данные',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Обновите информацию о себе',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            // Name Field
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Имя',
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
            const SizedBox(height: 24),

            // Email Field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_isGoogleUser, // Запрещаем редактирование для Google
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                helperText: _isGoogleUser
                    ? 'Email управляется через Google аккаунт'
                    : 'При изменении email потребуется подтверждение',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 40),

            // Save Button
            ElevatedButton(
              onPressed: _loading ? null : _updateProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                elevation: 2,
              ),
              child: _loading
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Text(
                      'Сохранить изменения',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

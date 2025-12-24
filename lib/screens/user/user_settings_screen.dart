import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/theme_service.dart';
import 'edit_profile_screen.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  String? _avatarUrl;
  String? _fullName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data =
          await Supabase.instance.client
              .from('profiles')
              .select('avatar_url, full_name')
              .eq('id', user.id)
              .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'];
          _fullName = data['full_name'];
        });
      }
    } catch (e) {
      // Handle error or profile not found
    }
  }

  Future<void> _updateAvatar() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(source: ImageSource.gallery);
    if (imageFile == null) return;

    setState(() => _loading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final fileExt = imageFile.path.split('.').last;
      final fileName =
          '${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Upload to Supabase Storage
      await Supabase.instance.client.storage
          .from('avatars')
          .upload(fileName, File(imageFile.path));

      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      // Update profile
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'avatar_url': imageUrl,
      });

      if (mounted) {
        setState(() {
          _avatarUrl = imageUrl;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Аватар обновлен')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления аватара: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();
    final user = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = _fullName ?? user?.userMetadata?['name'] as String? ?? 'Пользователь';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Section
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _updateAvatar,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          backgroundImage:
                              _avatarUrl != null
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                          child:
                              _avatarUrl == null
                                  ? Icon(
                                    Icons.person,
                                    size: 60,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )
                                  : null,
                        ),
                      ),
                      if (_loading)
                        const Positioned.fill(
                          child: CircularProgressIndicator(),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Settings Section
          Text(
            'Приложение',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color:
                isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.grey.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.dark_mode_rounded,
                      color: Colors.purple,
                    ),
                  ),
                  title: const Text('Темная тема'),
                  value: themeService.themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    themeService.toggleTheme();
                    setState(() {});
                  },
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.colorScheme.outline.withOpacity(0.1),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.blue,
                    ),
                  ),
                  title: const Text('Уведомления'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // TODO: Implement notifications settings
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Account Section
          Text(
            'Аккаунт',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color:
                isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.grey.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: Colors.orange,
                    ),
                  ),
                  title: const Text('Редактировать профиль'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    );
                    if (result == true) {
                      setState(() {}); // Обновляем экран, если профиль изменился
                    }
                  },
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.colorScheme.outline.withOpacity(0.1),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.red,
                    ),
                  ),
                  title: const Text(
                    'Выйти',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('Выход'),
                            content: const Text(
                              'Вы уверены, что хотите выйти?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await Supabase.instance.client.auth.signOut();
                                },
                                child: const Text(
                                  'Выйти',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Версия 1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

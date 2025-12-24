import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/theme_service.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  String? _avatarUrl;
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
              .select('avatar_url')
              .eq('id', user.id)
              .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'];
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

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          if (user != null)
            UserAccountsDrawerHeader(
              accountName: const Text('Пользователь'),
              accountEmail: Text(user.email ?? ''),
              currentAccountPicture: GestureDetector(
                onTap: _updateAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage:
                          _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                      child:
                          _avatarUrl == null
                              ? const Icon(Icons.person, size: 40)
                              : null,
                    ),
                    if (_loading)
                      const Positioned.fill(child: CircularProgressIndicator()),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Тема оформления'),
            trailing: IconButton(
              icon: Icon(
                themeService.themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              onPressed: () {
                themeService.toggleTheme();
                setState(() {}); // Rebuild to show change
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Выйти', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}

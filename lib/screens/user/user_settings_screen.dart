import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
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
  String? _phone;
  bool _loading = false;
  int _totalSaved = 0;
  int _totalPurchases = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadStats();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url, full_name, phone')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'];
          _fullName = data['full_name'];
          _phone = data['phone'];
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadStats() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('transactions')
          .select('discount_amount')
          .eq('customer_id', userId);
      
      if (mounted) {
        double totalSaved = 0;
        for (var t in data) {
          totalSaved += (t['discount_amount'] as num).toDouble();
        }
        setState(() {
          _totalSaved = totalSaved.toInt();
          _totalPurchases = data.length;
        });
      }
    } catch (e) {
      // Handle error
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
      final fileName = '${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await Supabase.instance.client.storage
          .from('avatars')
          .upload(fileName, File(imageFile.path));

      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'avatar_url': imageUrl,
      });

      if (mounted) {
        setState(() => _avatarUrl = imageUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Аватар обновлен'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления аватара: $e'),
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
    final themeService = ThemeService();
    final user = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = _fullName ?? user?.userMetadata?['name'] as String? ?? 'Пользователь';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.colorScheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Avatar
                      GestureDetector(
                        onTap: _updateAvatar,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                backgroundImage: _avatarUrl != null
                                    ? NetworkImage(_avatarUrl!)
                                    : null,
                                child: _avatarUrl == null
                                    ? const Icon(Icons.person, size: 50, color: Colors.white)
                                    : null,
                              ),
                            ),
                            if (_loading)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withOpacity(0.5),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Stats
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('$_totalSaved ₽', 'Сэкономлено'),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            _buildStatItem('$_totalPurchases', 'Покупок'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            title: const Text(
              'Профиль',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Section
                  _buildSectionTitle('Личные данные', Icons.person_outline, theme),
                  const SizedBox(height: 8),
                  _buildCard(
                    theme: theme,
                    isDark: isDark,
                    children: [
                      _buildListTile(
                        icon: Icons.edit,
                        iconColor: Colors.blue,
                        title: 'Редактировать профиль',
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                          );
                          if (result == true) _loadProfile();
                        },
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Subscription Section
                  _buildSectionTitle('Подписка', Icons.workspace_premium_outlined, theme),
                  const SizedBox(height: 8),
                  _buildCard(
                    theme: theme,
                    isDark: isDark,
                    children: [
                      _buildListTile(
                        icon: Icons.star,
                        iconColor: Colors.amber,
                        title: 'Управление подпиской',
                        subtitle: 'Планы и оплата',
                        onTap: () => context.push('/subscription'),
                        theme: theme,
                      ),
                      _buildDivider(theme),
                      _buildListTile(
                        icon: Icons.payment,
                        iconColor: Colors.green,
                        title: 'Способы оплаты',
                        subtitle: 'Банковские карты',
                        onTap: () => context.push('/payment'),
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // App Settings Section
                  _buildSectionTitle('Приложение', Icons.settings_outlined, theme),
                  const SizedBox(height: 8),
                  _buildCard(
                    theme: theme,
                    isDark: isDark,
                    children: [
                      SwitchListTile(
                        secondary: _buildIconContainer(Icons.dark_mode, Colors.purple),
                        title: const Text('Темная тема'),
                        subtitle: Text(
                          isDark ? 'Включена' : 'Выключена',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        value: themeService.themeMode == ThemeMode.dark,
                        onChanged: (value) {
                          themeService.toggleTheme();
                          setState(() {});
                        },
                        activeColor: theme.colorScheme.primary,
                      ),
                      _buildDivider(theme),
                      _buildListTile(
                        icon: Icons.notifications,
                        iconColor: Colors.orange,
                        title: 'Уведомления',
                        subtitle: 'Управление уведомлениями',
                        onTap: () {},
                        theme: theme,
                      ),
                      _buildDivider(theme),
                      _buildListTile(
                        icon: Icons.language,
                        iconColor: Colors.teal,
                        title: 'Язык',
                        subtitle: 'Русский',
                        onTap: () {},
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Support Section
                  _buildSectionTitle('Поддержка', Icons.help_outline, theme),
                  const SizedBox(height: 8),
                  _buildCard(
                    theme: theme,
                    isDark: isDark,
                    children: [
                      _buildListTile(
                        icon: Icons.info,
                        iconColor: Colors.blue,
                        title: 'О приложении',
                        onTap: () {},
                        theme: theme,
                      ),
                      _buildDivider(theme),
                      _buildListTile(
                        icon: Icons.description,
                        iconColor: Colors.indigo,
                        title: 'Политика конфиденциальности',
                        onTap: () {},
                        theme: theme,
                      ),
                      _buildDivider(theme),
                      _buildListTile(
                        icon: Icons.support_agent,
                        iconColor: Colors.cyan,
                        title: 'Связаться с поддержкой',
                        onTap: () {},
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Logout Section
                  _buildCard(
                    theme: theme,
                    isDark: isDark,
                    children: [
                      _buildListTile(
                        icon: Icons.logout,
                        iconColor: Colors.red,
                        title: 'Выйти из аккаунта',
                        titleColor: Colors.red,
                        onTap: () => _showLogoutDialog(context, theme),
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Version
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.savings,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ziroo',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Версия 1.0.0',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required ThemeData theme,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildIconContainer(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return ListTile(
      leading: _buildIconContainer(icon, iconColor),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: titleColor,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            )
          : null,
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey[400],
      ),
      onTap: onTap,
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 72,
      endIndent: 16,
      color: theme.colorScheme.outline.withOpacity(0.1),
    );
  }

  void _showLogoutDialog(BuildContext context, ThemeData theme) {
    final goRouter = GoRouter.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Выход'),
          ],
        ),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await Supabase.instance.client.auth.signOut();
              goRouter.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

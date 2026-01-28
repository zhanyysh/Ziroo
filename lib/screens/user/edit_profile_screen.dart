import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'change_email_screen.dart';
import 'change_phone_screen.dart';
import 'change_password_screen.dart';

/// Экран редактирования профиля
/// 
/// АРХИТЕКТУРА (с триггером синхронизации):
/// - Обновляем auth.users через updateUser()
/// - Триггер sync_profile_from_auth() автоматически синхронизирует в profiles
/// - Email/Phone: только для чтения (изменение требует верификации)
/// 
/// Что можно редактировать:
/// - Имя (full_name) → auth.raw_user_meta_data → триггер → profiles
/// - Аватар (avatar_url) → storage + auth → триггер → profiles
/// 
/// Что НЕЛЬЗЯ редактировать здесь:
/// - Email → требует подтверждения через Supabase Auth flow
/// - Phone → требует OTP верификации
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;
  
  // Данные профиля
  String? _email;
  String? _phone;
  String? _avatarUrl;
  String? _provider; // google, email, phone
  
  File? _newAvatarFile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Загрузка данных профиля из таблицы profiles
  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() => _errorMessage = 'Пользователь не авторизован');
        return;
      }

      // Получаем данные из profiles (основной источник)
      final profileData = await _supabase
          .from('profiles')
          .select('full_name, email, phone, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // Приоритет: profiles → auth
          _nameController.text = profileData?['full_name'] ?? 
                                  user.userMetadata?['name'] ?? 
                                  user.userMetadata?['full_name'] ?? '';
          _email = profileData?['email'] ?? user.email;
          _phone = profileData?['phone'] ?? user.phone;
          _avatarUrl = profileData?['avatar_url'] ?? user.userMetadata?['avatar_url'];
          _provider = user.appMetadata['provider'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Ошибка загрузки: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Выбор и обрезка аватара
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Фото профиля',
          toolbarColor: Colors.deepPurple,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
        ),
        IOSUiSettings(
          title: 'Фото профиля',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile != null && mounted) {
      setState(() {
        _newAvatarFile = File(croppedFile.path);
      });
    }
  }

  /// Загрузка аватара в Storage
  Future<String?> _uploadAvatar(String userId) async {
    if (_newAvatarFile == null) return null;

    try {
      final fileExt = _newAvatarFile!.path.split('.').last;
      final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Загружаем в storage
      await _supabase.storage
          .from('avatars')
          .upload(
            fileName,
            _newAvatarFile!,
            fileOptions: const FileOptions(upsert: true),
          );

      // Получаем публичный URL
      final imageUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      debugPrint('Ошибка загрузки аватара: $e');
      return null;
    }
  }

  /// Сохранение профиля
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');

      final newName = _nameController.text.trim();
      
      // 1. Загружаем аватар если изменился
      String? newAvatarUrl;
      if (_newAvatarFile != null) {
        newAvatarUrl = await _uploadAvatar(user.id);
        if (newAvatarUrl == null) {
          throw Exception('Не удалось загрузить фото');
        }
      }

      // 2. Обновляем auth.users - триггер автоматически синхронизирует в profiles
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': newName,
            'name': newName,
            if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
          },
        ),
      );

      // 3. Успех - триггер sync_profile_from_auth() уже обновил profiles
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Профиль успешно обновлен'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // true = данные изменились
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ошибка
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Аватар
                    Center(
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              backgroundImage: _getAvatarImage(),
                              child: _shouldShowPlaceholder()
                                  ? Icon(
                                      Icons.person,
                                      size: 60,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    )
                                  : null,
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
                                    color: theme.colorScheme.surface,
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
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Нажмите чтобы изменить фото',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Имя
                    TextFormField(
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
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя';
                        }
                        if (value.trim().length < 2) {
                          return 'Имя должно быть не менее 2 символов';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Email (кликабельный для смены)
                    _buildEditableField(
                      label: 'Email',
                      value: _email ?? 'Не указан',
                      icon: Icons.email_outlined,
                      helperText: _provider == 'google'
                          ? 'Управляется через Google аккаунт'
                          : 'Нажмите чтобы изменить',
                      theme: theme,
                      isDark: isDark,
                      isEditable: _provider != 'google',
                      onTap: _provider != 'google' ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChangeEmailScreen(),
                          ),
                        );
                      } : null,
                    ),
                    const SizedBox(height: 24),

                    // Телефон (кликабельный для смены)
                    _buildEditableField(
                      label: 'Телефон',
                      value: _phone ?? 'Не указан',
                      icon: Icons.phone_outlined,
                      helperText: 'Нажмите чтобы изменить',
                      theme: theme,
                      isDark: isDark,
                      isEditable: true,
                      onTap: () async {
                        final changed = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChangePhoneScreen(),
                          ),
                        );
                        if (changed == true) {
                          _loadProfile(); // Перезагружаем данные
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Пароль (установить/сменить)
                    _buildEditableField(
                      label: 'Пароль',
                      value: _provider == 'email' ? '••••••••' : 'Не установлен',
                      icon: Icons.lock_outline,
                      helperText: _provider == 'email' 
                          ? 'Нажмите чтобы сменить'
                          : 'Установите для входа по email',
                      theme: theme,
                      isDark: isDark,
                      isEditable: _provider != 'google',
                      onTap: _provider != 'google' ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen(),
                          ),
                        );
                      } : null,
                    ),
                    const SizedBox(height: 40),

                    // Кнопка сохранения
                    ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Получить изображение аватара
  ImageProvider? _getAvatarImage() {
    if (_newAvatarFile != null) {
      return FileImage(_newAvatarFile!);
    }
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return NetworkImage(_avatarUrl!);
    }
    return null;
  }

  /// Показывать ли placeholder
  bool _shouldShowPlaceholder() {
    return _newAvatarFile == null && (_avatarUrl == null || _avatarUrl!.isEmpty);
  }

  /// Поле только для чтения
  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required String helperText,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 6),
          child: Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// Поле с возможностью редактирования (переход на другой экран)
  Widget _buildEditableField({
    required String label,
    required String value,
    required IconData icon,
    required String helperText,
    required ThemeData theme,
    required bool isDark,
    required bool isEditable,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isEditable ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isEditable 
                      ? theme.colorScheme.primary.withOpacity(0.3)
                      : theme.colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: isEditable 
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isEditable ? Icons.chevron_right : Icons.lock_outline,
                    size: isEditable ? 24 : 18,
                    color: isEditable 
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 6),
          child: Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isEditable 
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

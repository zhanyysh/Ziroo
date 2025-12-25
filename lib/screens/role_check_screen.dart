import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class RoleCheckScreen extends StatefulWidget {
  const RoleCheckScreen({super.key});

  @override
  State<RoleCheckScreen> createState() => _RoleCheckScreenState();
}

class _RoleCheckScreenState extends State<RoleCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // Если пользователя нет, роутер сам перекинет на логин, 
        // но на всякий случай можно явно отправить
        if (mounted) context.go('/login');
        return;
      }

      final data =
          await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();

      if (!mounted) return;

      final role = data?['role'] as String? ?? 'user';

      if (role == 'admin') {
        // Админку пока не переводили на go_router полностью, 
        // но можно сделать простой переход
        // context.go('/admin'); 
        // Пока оставим как есть, но GoRouter требует путей.
        // В router.dart я не добавил /admin как ShellRoute, а как простой Route.
        // Поэтому просто переходим на /admin
        // Но у нас AdminDashboard не адаптирован. 
        // Для теста клиента (User) это не критично.
        // Давайте пока просто перенаправим на /home если роль user
        // А если админ - покажем заглушку или попробуем /admin
         context.go('/admin/home');
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        context.go('/home'); // Fallback
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

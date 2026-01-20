import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Импорты экранов
import 'screens/login_screen.dart';
import 'screens/user_screen.dart';
import 'screens/user/user_main_screen.dart';
import 'screens/map_screen.dart';
import 'screens/user/user_history_screen.dart';
import 'screens/user/user_settings_screen.dart';
import 'screens/user/company_details_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/admin_history_screen.dart';
import 'screens/admin/admin_companies_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/manager/manager_dashboard.dart';
import 'screens/manager/manager_home_screen.dart';
import 'screens/manager/manager_scan_screen.dart';
import 'screens/manager/manager_history_screen.dart';
import 'screens/manager/manager_settings_screen.dart';
import 'widgets/auth_wrapper.dart';

// Ключи навигации нужны для управления стеком
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/', // Начинаем с проверки авторизации
  
  routes: [
    // Корневой маршрут - AuthWrapper (пока оставим его для проверки роли)
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthWrapper(),
    ),
    
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    // Админ панель (ShellRoute)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AdminDashboard(navigationShell: navigationShell);
      },
      branches: [
        // Ветка 0: История
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/history',
              builder: (context, state) => const HistoryScreen(),
            ),
          ],
        ),
        // Ветка 1: Магазины
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/companies',
              builder: (context, state) => const CompaniesScreen(),
            ),
          ],
        ),
        // Ветка 2: Главная (Home)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/home',
              builder: (context, state) => const AdminHomeScreen(),
            ),
          ],
        ),
        // Ветка 3: Карта
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        // Ветка 4: Настройки
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // Панель менеджера (ShellRoute)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ManagerDashboard(navigationShell: navigationShell);
      },
      branches: [
        // Ветка 0: Главная
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/manager/home',
              builder: (context, state) => const ManagerHomeScreen(),
            ),
          ],
        ),
        // Ветка 1: Сканер QR
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/manager/scan',
              builder: (context, state) => const ManagerScanScreen(),
            ),
          ],
        ),
        // Ветка 2: История транзакций
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/manager/history',
              builder: (context, state) => const ManagerHistoryScreen(),
            ),
          ],
        ),
        // Ветка 3: Настройки
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/manager/settings',
              builder: (context, state) => const ManagerSettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // Оболочка для нижней навигации пользователя
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        // Мы передаем navigationShell в UserScreen, чтобы он управлял табами
        return UserScreen(navigationShell: navigationShell);
      },
      branches: [
        // Ветка 1: Главная
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const UserMainScreen(),
              routes: [
                // Детали компании (вложенный маршрут, чтобы скрыть нижнюю панель, 
                // используем parentNavigatorKey: _rootNavigatorKey)
                GoRoute(
                  path: 'company',
                  parentNavigatorKey: _rootNavigatorKey, 
                  builder: (context, state) {
                    final company = state.extra as Map<String, dynamic>;
                    return CompanyDetailsScreen(company: company);
                  },
                ),
              ],
            ),
          ],
        ),

        // Ветка 2: Карта
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),

        // Ветка 3: История (пропускаем индекс для FAB)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) => const UserHistoryScreen(),
            ),
          ],
        ),

        // Ветка 4: Настройки
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const UserSettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

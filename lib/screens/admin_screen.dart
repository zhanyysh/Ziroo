// lib/screens/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'users_screen.dart';        // ← сейчас
import 'companies_screen.dart'; // ← потом просто раскомментируешь

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  // ←←← ВСЁ, ЧТО НУЖНО МЕНЯТЬ ПРИ ДОБАВЛЕНИИ НОВЫХ РАЗДЕЛОВ — ЭТОТ СПИСОК
  static final List<AdminMenuItem> menuItems = [
    AdminMenuItem(
      icon: Icons.people_alt_outlined,
      title: 'Users Panel',
      subtitle: 'Manage users, roles & delete accounts',
      color: Colors.blue,
      screen: const UsersScreen(),
    ),

    // ← Просто добавляй новые элементы сюда:
    AdminMenuItem(
      icon: Icons.business,
      title: 'Companies',
      subtitle: 'Manage organizations and plans',
      color: Colors.green,
      screen: const CompaniesScreen(),
    ),

  ];
  // ←←← КОНЕЦ СПИСКА

  @override
  Widget build(BuildContext context) {
    final bool isSingleItem = menuItems.length == 1;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: isSingleItem
          ? _buildSingleCard(context)                // ← 1 карточка → красиво по центру
          : _buildGrid(screenWidth),                  // ← много карточек → сетка
    );
  }

  // Одна карточка — большая и по центру
  Widget _buildSingleCard(BuildContext context) {
    final item = menuItems.first;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildCard(context, item, isLarge: true),
      ),
    );
  }

  // Несколько карточек — адаптивная сетка
  Widget _buildGrid(double screenWidth) {
    final int crossAxisCount = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.4,
        ),
        itemCount: menuItems.length,
        itemBuilder: (context, index) => _buildCard(context, menuItems[index]),
      ),
    );
  }

  Widget _buildCard(BuildContext context, AdminMenuItem item, {bool isLarge = false}) {
    final double iconSize = isLarge ? 56 : 40;
    final double titleSize = isLarge ? 26 : 18;
    final double subtitleSize = isLarge ? 16 : 13;

    return Card(
      elevation: isLarge ? 16 : 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isLarge ? 28 : 20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(isLarge ? 28 : 20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screen)),
        child: Container(
          constraints: isLarge ? const BoxConstraints(maxWidth: 420) : null,
          padding: EdgeInsets.all(isLarge ? 36 : 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: isLarge ? 56 : 36,
                backgroundColor: item.color.withOpacity(0.15),
                child: Icon(item.icon, size: iconSize, color: item.color),
              ),
              const SizedBox(height: 20),
              Text(
                item.title,
                style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                item.subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: subtitleSize),
                textAlign: TextAlign.center,
              ),
              if (isLarge) ...[
                const SizedBox(height: 24),
                Icon(Icons.arrow_forward_ios, color: item.color, size: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ←←← КЛАСС-ОБОЛОЧКА — добавляй новые экраны и всё!
class AdminMenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget screen;

  AdminMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.screen,
  });
}
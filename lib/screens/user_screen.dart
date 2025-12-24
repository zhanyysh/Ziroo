import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'user/user_main_screen.dart';
import 'user/user_history_screen.dart';
import 'user/user_settings_screen.dart';
import 'map_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const UserMainScreen(),
    const MapScreen(),
    const SizedBox(), // Placeholder for QR button
    const UserHistoryScreen(),
    const UserSettingsScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == 2) return; // QR button handled separately
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showQrCode() {
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? 'unknown';
    final email = user?.email ?? '';
    // Пытаемся получить имя из метаданных, если есть
    final name = user?.userMetadata?['name'] as String? ?? 'ПОЛЬЗОВАТЕЛЬ';
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 14, 
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: userId,
                      version: QrVersions.auto,
                      size: 250.0,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H, // Высокий уровень коррекции ошибок для логотипа
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      padding: const EdgeInsets.all(4), // Белая рамка вокруг логотипа
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/images/logo.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('Error loading logo: $error');
                            return Container(
                              color: const Color(0xFF40C4C6),
                              child: const Center(
                                child: Icon(Icons.store, color: Colors.white, size: 30),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Логотип Ziroo внизу (текст или картинка)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF40C4C6), // Цвет логотипа Ziroo
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.qr_code, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Ziroo',
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF40C4C6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      floatingActionButton: SizedBox(
        width: 70,
        height: 70,
        child: FloatingActionButton(
          onPressed: _showQrCode,
          backgroundColor: const Color(0xFF40C4C6), // Ziroo color
          shape: const CircleBorder(),
          elevation: 4,
          child: const Icon(Icons.qr_code, size: 36, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.home, 'Главная'),
            _buildNavItem(1, Icons.map, 'Карта'),
            const SizedBox(width: 48), // Space for FAB
            _buildNavItem(3, Icons.history, 'История'),
            _buildNavItem(4, Icons.settings, 'Ещё'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class LocationService {
  /// Проверяет и запрашивает разрешения на геолокацию.
  /// Возвращает true, если доступ получен.
  /// Может показать диалог настроек, если context передан и служба выключена.
  Future<bool> checkPermission({BuildContext? context}) async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Проверяем включена ли служба GPS
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context != null && context.mounted) {
        final openSettings = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Геолокация выключена'),
                content: const Text(
                  'Для определения местоположения включите геолокацию.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Включить'),
                  ),
                ],
              ),
        );

        if (openSettings == true) {
          await Geolocator.openLocationSettings();
          // Можно рекурсивно проверить снова, но обычно пользователь возвращается сам
        }
      }
      return false;
    }

    // 2. Проверяем разрешения приложения
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Разрешение на геолокацию отклонено')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Геолокация запрещена навсегда. Измените в настройках.',
            ),
          ),
        );
      }
      return false;
    }

    return true;
  }

  /// Получает последнее известное местоположение (быстро)
  Future<Position?> getLastKnownPosition() async {
    return await Geolocator.getLastKnownPosition();
  }

  /// Получает точное текущее местоположение
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint("Error getting location: $e");
      return null;
    }
  }

  /// Стрим обновлений позиции
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }
}

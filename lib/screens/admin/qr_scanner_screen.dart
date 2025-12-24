import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'user_details_screen.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isScanning = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR-код')),
      body: MobileScanner(
        onDetect: (capture) {
          if (!_isScanning) return;
          
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              setState(() {
                _isScanning = false;
              });
              
              final String userId = barcode.rawValue!;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => UserDetailsScreen(userId: userId),
                ),
              );
              break; 
            }
          }
        },
      ),
    );
  }
}

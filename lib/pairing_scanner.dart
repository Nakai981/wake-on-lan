import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pairing_qr.dart';

class PairingScannerPage extends StatefulWidget {
  const PairingScannerPage({super.key});
  @override
  State<PairingScannerPage> createState() => _PairingScannerPageState();
}

class _PairingScannerPageState extends State<PairingScannerPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool completed = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét QR Windows Agent')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: controller,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Không mở được camera. Hãy cấp quyền Camera trong cài đặt hoặc quay lại để nhập mã bằng tay.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            onDetect: (capture) {
              if (completed) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw == null) continue;
                try {
                  final qr = PairingQr.parse(raw);
                  completed = true;
                  Navigator.pop(context, qr);
                  return;
                } on FormatException catch (e) {
                  setState(() => error = e.message);
                }
              }
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              error ?? 'Trên PC: mở Agent → Hiện QR ghép nối. Đưa mã QR vào khung camera.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    ),
  );
}

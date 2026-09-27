import 'models.dart';

class PairingQr {
  final String ip, mac, key;
  const PairingQr(this.ip, this.mac, this.key);

  factory PairingQr.parse(String raw) {
    try {
      if (raw.length > 512) throw const FormatException();
      final uri = Uri.parse(raw);
      final q = uri.queryParameters;
      if (uri.scheme != 'wakemypc' ||
          uri.host != 'pair' ||
          uri.path.isNotEmpty ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          q.length != 4 ||
          q['v'] != '1' ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        throw const FormatException();
      }
      final ip = q['ip']!;
      final n = ipv4Number(ip);
      if (n >> 24 == 0 || n >> 24 == 127 || n >> 24 >= 224) {
        throw const FormatException();
      }
      final key = q['key']!;
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)) {
        throw const FormatException();
      }
      return PairingQr(ip, normalizeMac(q['mac']!), key.toLowerCase());
    } catch (_) {
      throw const FormatException(
        'QR không phải mã ghép nối Wake My PC hợp lệ.',
      );
    }
  }
}

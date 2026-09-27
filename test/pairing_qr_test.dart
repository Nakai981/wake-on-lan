import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/pairing_qr.dart';
import 'package:wake_my_pc/models.dart';

void main() {
  const payload =
      'wakemypc://pair?v=1&ip=192.168.1.20&mac=A4%3ABB%3A6D%3A12%3A34%3A56&key=0123456789abcdef0123456789abcdef';
  test('reads Windows QR and preserves PC settings when updating IP', () {
    final qr = PairingQr.parse(payload);
    expect(qr.ip, '192.168.1.20');
    expect(qr.mac, 'A4:BB:6D:12:34:56');
    expect(qr.key, '0123456789abcdef0123456789abcdef');
    final pc = Pc(
      id: 'saved',
      name: 'PC',
      mac: qr.mac,
      favorite: true,
      network: '192.168.1.0/255.255.255.0',
    );
    final paired = pc.copy(ip: qr.ip, agentPaired: true);
    expect(paired.id, pc.id);
    expect(paired.favorite, isTrue);
    expect(paired.network, pc.network);
    expect(paired.agentPaired, isTrue);
    expect(paired.ip, qr.ip);
  });
  test('rejects foreign, malformed, duplicate and unsupported QR payloads', () {
    for (final bad in [
      'https://example.com',
      payload.replaceFirst('v=1', 'v=2'),
      '$payload&v=1',
      payload.replaceFirst('192.168.1.20', '127.0.0.1'),
      payload.replaceFirst('192.168.1.20', '999.1.1.1'),
      payload.replaceFirst('key=', 'other='),
      payload.replaceFirst('A4%3A', 'FF%3A'),
      payload.replaceFirst('0123456789abcdef0123456789abcdef', 'abc'),
    ]) {
      expect(() => PairingQr.parse(bad), throwsFormatException);
    }
  });
}

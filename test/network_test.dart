import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

void main() {
  test('normalizes MAC and rejects malformed or multicast addresses', () {
    expect(normalizeMac(' a4-bb-6d-12-34-56 '), 'A4:BB:6D:12:34:56');
    for (final bad in [
      'AA:BB',
      'GG:BB:CC:DD:EE:FF',
      'FF:FF:FF:FF:FF:FF',
      '00:00:00:00:00:00',
    ]) {
      expect(() => normalizeMac(bad), throwsFormatException);
    }
  });
  test('magic packet has six FF bytes and sixteen complete MAC copies', () {
    final packet = magicPacket('A4:BB:6D:12:34:56');
    expect(packet.length, 102);
    expect(packet.take(6), List.filled(6, 255));
    for (var n = 0; n < 16; n++) {
      expect(packet.sublist(6 + n * 6, 12 + n * 6), [
        164,
        187,
        109,
        18,
        52,
        86,
      ]);
    }
  });
  test('subnet math supports non /24 networks and excludes boundaries', () {
    final lan = Lan('192.168.2.140', '255.255.255.128');
    expect(lan.broadcast, '192.168.2.255');
    expect(lan.hosts.length, 125);
    expect(lan.hosts, isNot(contains('192.168.2.140')));
    expect(lan.contains('192.168.2.127'), isFalse);
    expect(lan.contains('192.168.2.200'), isTrue);
    expect(Lan('10.2.4.5', '255.0.0.0').hosts.length, 253);
    expect(() => Lan('1.2.3.4', '255.0.255.0'), throwsFormatException);
    expect(() => ipv4Number('256.1.1.1'), throwsFormatException);
  });
  test('persists devices and capped history across store instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DeviceStore(prefs);
    const pc = Pc(
      id: '1',
      name: 'PC Gaming',
      mac: 'A4:BB:6D:12:34:56',
      favorite: true,
    );
    await store.save([pc]);
    expect(DeviceStore(prefs).read().single.toJson(), pc.toJson());
    for (var i = 0; i < 65; i++) {
      await store.log('event $i');
    }
    expect(store.history().length, 60);
    expect(store.history().first, endsWith('|event 64'));
  });
  test('sends actual UDP bytes and configured repeat count', () async {
    final receiver = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final packets = <List<int>>[];
    final subscription = receiver.listen((event) {
      if (event == RawSocketEvent.read) {
        final packet = receiver.receive();
        if (packet != null) packets.add(packet.data);
      }
    });
    try {
      await NetworkService().wake(
        Pc(
          id: 'test',
          name: 'test',
          mac: 'A4:BB:6D:12:34:56',
          broadcast: '127.0.0.1',
          port: receiver.port,
          retries: 3,
        ),
        Lan('127.0.0.1', '255.0.0.0'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(packets.length, 3);
      for (final packet in packets) {
        expect(packet, magicPacket('A4:BB:6D:12:34:56'));
      }
    } finally {
      await subscription.cancel();
      receiver.close();
    }
  });
}

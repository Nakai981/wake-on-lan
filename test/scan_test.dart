import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class ProbeNetwork extends NetworkService {
  int active = 0, maximum = 0, calls = 0;
  @override
  Future<bool> reachable(String ip) async {
    active++;
    calls++;
    if (active > maximum) maximum = active;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    active--;
    return ip.endsWith('.2');
  }
}

void main() {
  test(
    'scanner bounds concurrency and reports only responding hosts',
    () async {
      final net = ProbeNetwork();
      final found = <String>[];
      var completed = 0;
      await net.scan(
        Lan('192.168.1.1', '255.255.255.0'),
        cancelled: () => false,
        progress: (done, total, ip) {
          completed = done;
          expect(total, 253);
          if (ip != null) found.add(ip);
        },
      );
      expect(completed, 253);
      expect(net.maximum, lessThanOrEqualTo(12));
      expect(found, ['192.168.1.2']);
    },
  );
  test('cancel stops scheduling hosts and suppresses late progress', () async {
    final net = ProbeNetwork();
    var cancelled = false, updates = 0;
    await net.scan(
      Lan('192.168.1.1', '255.255.255.0'),
      cancelled: () => cancelled,
      progress: (_, total, ip) {
        updates++;
        cancelled = true;
      },
    );
    expect(updates, 1);
    expect(net.calls, lessThanOrEqualTo(12));
    expect(net.active, 0);
  });
}

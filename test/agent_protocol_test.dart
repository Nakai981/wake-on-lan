import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/agent_client.dart';

const testCode = '0123456789abcdef0123456789abcdef';
void main() {
  test('pair code validation and constant-time signature comparison', () {
    expect(normalizePairCode('01234567-89ABCDEF-01234567-89ABCDEF'), testCode);
    expect(() => normalizePairCode('123456'), throwsFormatException);
    expect(equalSignature('abc', 'abd'), isFalse);
    expect(equalSignature('abc', 'abc'), isTrue);
  });
  test('client rejects forged server acknowledgement', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final done = Completer<void>();
    server.listen((socket) async {
      try {
        socket.write('WMP1 ${List.filled(64, 'a').join()}\n');
        await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        socket.write('accepted ${List.filled(64, '0').join()}\n');
        await socket.flush();
      } finally {
        socket.destroy();
        done.complete();
      }
    });
    try {
      await expectLater(
        const AgentClient().request(
          '127.0.0.1',
          testCode,
          'sleep',
          port: server.port,
        ),
        throwsFormatException,
      );
      await done.future;
    } finally {
      await server.close();
    }
  });
  final portText = Platform.environment['WMP_TEST_PORT'];
  if (portText != null) {
    final port = int.parse(portText);
    test(
      'Dart interoperates with real C# agent, power remains simulated',
      () async {
        const client = AgentClient();
        expect(
          await client.request('127.0.0.1', testCode, 'status', port: port),
          'online',
        );
        for (final command in ['sleep', 'shutdown', 'cancel']) {
          expect(
            await client.request('127.0.0.1', testCode, command, port: port),
            'simulated',
          );
        }
        await expectLater(
          client.request(
            '127.0.0.1',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'shutdown',
            port: port,
          ),
          throwsA(isA<SocketException>()),
        );
      },
    );
    test('captured request cannot be replayed on a fresh C# challenge', () async {
      final first = await Socket.connect('127.0.0.1', port);
      final lines = StreamIterator(
        first
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      await lines.moveNext();
      final challenge = lines.current.split(' ')[1];
      final nonce = List.filled(64, 'b').join();
      final request =
          'sleep $nonce ${signAgent(testCode, 'request\n$challenge\n$nonce\nsleep')}\n';
      first.write(request);
      await lines.moveNext();
      expect(lines.current.startsWith('simulated '), isTrue);
      first.destroy();
      await lines.cancel();
      final second = await Socket.connect('127.0.0.1', port);
      final next = StreamIterator(
        second
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      await next.moveNext();
      expect(next.current.split(' ')[1], isNot(challenge));
      second.write(request);
      expect(
        await next.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
      second.destroy();
      await next.cancel();
    });
  }
}

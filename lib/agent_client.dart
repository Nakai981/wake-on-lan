import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

const agentPort = 47991;
String normalizePairCode(String value) {
  final code = value.trim().replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(code)) {
    throw const FormatException('Nhập mã 32 ký tự từ Windows Agent.');
  }
  return code;
}

List<int> secretBytes(String code) => [
  for (var i = 0; i < code.length; i += 2)
    int.parse(code.substring(i, i + 2), radix: 16),
];
String signAgent(String code, String message) =>
    Hmac(sha256, secretBytes(code)).convert(utf8.encode(message)).toString();
bool equalSignature(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

class AgentClient {
  final FlutterSecureStorage storage;
  const AgentClient({this.storage = const FlutterSecureStorage()});
  Future<String?> keyFor(String id) => storage.read(key: 'agent.$id');
  Future<void> forget(String id) => storage.delete(key: 'agent.$id');
  Future<void> pair(Pc pc, String input) async {
    final code = normalizePairCode(input);
    final result = await request(pc.ip, code, 'status');
    if (result != 'online') throw const SocketException('Agent chưa sẵn sàng.');
    await storage.write(key: 'agent.${pc.id}', value: code);
  }

  Future<String> command(Pc pc, String command) async {
    final code = await keyFor(pc.id);
    if (code == null) throw StateError('Hãy ghép nối Windows Agent trước.');
    return request(pc.ip, code, command);
  }

  Future<String> request(
    String ip,
    String code,
    String command, {
    int port = agentPort,
  }) async {
    ipv4Number(ip);
    if (!{'status', 'sleep', 'shutdown', 'cancel'}.contains(command)) {
      throw ArgumentError('Lệnh không hỗ trợ');
    }
    normalizePairCode(code);
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(seconds: 3),
    );
    final lines = StreamIterator(
      socket.expand((chunk) => chunk).transform(const _BoundedLines()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 4))) {
        throw const SocketException('Agent không phản hồi.');
      }
      final hello = lines.current.split(' ');
      if (hello.length != 2 ||
          hello[0] != 'WMP1' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hello[1])) {
        throw const FormatException('Agent không hợp lệ.');
      }
      final challenge = hello[1];
      final random = Random.secure();
      final nonce = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      socket.write(
        '$command $nonce ${signAgent(code, 'request\n$challenge\n$nonce\n$command')}\n',
      );
      await socket.flush();
      if (!await lines.moveNext().timeout(const Duration(seconds: 4))) {
        throw const SocketException(
          'Sai mã ghép nối hoặc Agent đã đóng kết nối.',
        );
      }
      final reply = lines.current.split(' ');
      if (reply.length != 2 ||
          !equalSignature(
            reply[1],
            signAgent(
              code,
              'response\n$challenge\n$nonce\n$command\n${reply[0]}',
            ),
          )) {
        throw const FormatException('Không xác thực được phản hồi từ PC.');
      }
      if (!{
        'online',
        'accepted',
        'cancelled',
        'busy',
        'simulated',
      }.contains(reply[0])) {
        throw const FormatException('Phản hồi không hợp lệ.');
      }
      return reply[0];
    } finally {
      socket.destroy();
      await lines.cancel();
    }
  }
}

class _BoundedLines extends StreamTransformerBase<int, String> {
  const _BoundedLines();
  @override
  Stream<String> bind(Stream<int> stream) async* {
    final bytes = <int>[];
    await for (final byte in stream) {
      if (byte == 10) {
        yield ascii.decode(bytes);
        bytes.clear();
      } else {
        if (byte < 32 || byte > 126 || bytes.length >= 512) {
          throw const FormatException('Phản hồi quá dài hoặc không hợp lệ.');
        }
        bytes.add(byte);
      }
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class DeviceStore {
  final SharedPreferences prefs;
  DeviceStore(this.prefs);
  List<Pc> read() {
    final raw = prefs.getString('devices');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((j) => Pc.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<void> save(List<Pc> pcs) async {
    if (!await prefs.setString(
      'devices',
      jsonEncode(pcs.map((p) => p.toJson()).toList()),
    )) {
      throw const FileSystemException('Không lưu được dữ liệu.');
    }
  }

  List<String> history() => prefs.getStringList('history') ?? [];
  Future<void> log(String text) async {
    final items = [
      '${DateTime.now().toIso8601String()}|$text',
      ...history(),
    ].take(60).toList();
    if (!await prefs.setStringList('history', items)) {
      throw const FileSystemException('Không lưu được lịch sử.');
    }
  }
}

class NetworkService {
  Future<Lan?> network() async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    final mask = await info.getWifiSubmask();
    if (ip == null || mask == null || ip == '0.0.0.0') return null;
    return Lan(ip, mask);
  }

  // Only a successful connection is positive evidence. Silence is unknown.
  Future<bool> reachable(String ip) async {
    if (ip.isEmpty) return false;
    ipv4Number(ip);
    final results = await Future.wait(
      [445, 3389, 22, 80].map((port) async {
        Socket? socket;
        try {
          socket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(milliseconds: 450),
          );
          return true;
        } on SocketException {
          return false;
        } finally {
          socket?.destroy();
        }
      }),
    );
    return results.any((r) => r);
  }

  Future<String?> macFor(String ip) async {
    if (!Platform.isAndroid) return null;
    try {
      final mac = await const MethodChannel('wake_my_pc/lan')
          .invokeMethod<String>('mac', ip);
      return mac == null ? null : normalizeMac(mac);
    } catch (_) {
      return null;
    }
  }

  Future<void> scan(
    Lan lan, {
    required bool Function() cancelled,
    required void Function(int done, int total, String? found) progress,
  }) async {
    final hosts = lan.hosts;
    var next = 0, done = 0;
    await Future.wait(
      List.generate(12, (_) async {
        while (!cancelled() && next < hosts.length) {
          final ip = hosts[next++];
          final found = await reachable(ip);
          done++;
          if (!cancelled()) progress(done, hosts.length, found ? ip : null);
        }
      }),
    );
  }

  Future<void> wake(Pc pc, Lan lan) async {
    final target = pc.broadcast.isEmpty ? lan.broadcast : pc.broadcast;
    ipv4Number(target);
    final packet = magicPacket(pc.mac);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      for (var i = 0; i < pc.retries; i++) {
        if (socket.send(packet, InternetAddress(target), pc.port) !=
            packet.length) {
          throw const SocketException('Không gửi được tín hiệu.');
        }
        if (i + 1 < pc.retries) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      socket.close();
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'power_delay.dart';

class DeviceStore {
  final SharedPreferences prefs;
  DeviceStore(this.prefs);
  int get powerDelaySeconds {
    final seconds = prefs.getInt('powerDelaySeconds') ?? defaultPowerDelay;
    return validPowerDelay(seconds) ? seconds : defaultPowerDelay;
  }

  Future<void> savePowerDelay(int seconds) async {
    if (!validPowerDelay(seconds)) {
      throw const FormatException('Nhập thời gian từ 1 đến 86400 giây.');
    }
    if (!await prefs.setInt('powerDelaySeconds', seconds)) {
      throw const FileSystemException('Không lưu được thời gian chờ.');
    }
  }

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
      [47991, 445, 3389, 22, 80].map((port) async {
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

  Future<String?> nameFor(String ip) async {
    try {
      ipv4Number(ip);
      final result = await InternetAddress(ip)
          .reverse()
          .timeout(const Duration(seconds: 2));
      return result.host == ip ? null : result.host;
    } catch (_) {
      return null;
    }
  }

  Future<bool> discover(String ip) async {
    if (await reachable(ip)) return true;
    final replies = await Future.wait(
      [47991, 445, 3389, 22, 80].map((port) async {
        Socket? socket;
        try {
          socket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(milliseconds: 450),
          );
          return true;
        } on SocketException catch (e) {
          return [61, 111, 10061].contains(e.osError?.errorCode);
        } finally {
          socket?.destroy();
        }
      }),
    );
    return replies.any((reply) => reply);
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
          final found = await discover(ip);
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
    final trace = Zone.current[#wakeTrace] as void Function(String)?;
    trace?.call('UDP → $target:${pc.port} · MAC ${pc.mac}');
    trace?.call(
      'Magic Packet ${packet.length} byte: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase()}',
    );
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      for (var i = 0; i < pc.retries; i++) {
        final sent = socket.send(packet, InternetAddress(target), pc.port);
        if (sent != packet.length) {
          throw const SocketException('Không gửi được tín hiệu.');
        }
        trace?.call(
          'Lần ${i + 1}/${pc.retries}: socket đã gửi $sent byte → $target:${pc.port}',
        );
        if (i + 1 < pc.retries) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      socket.close();
    }
  }

  Future<void> wakeWithLog(Pc pc, Lan lan, void Function(String) log) =>
      runZoned(() => wake(pc, lan), zoneValues: {#wakeTrace: log});
}

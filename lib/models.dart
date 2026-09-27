import 'dart:typed_data';

String normalizeMac(String input) {
  final value = input.trim().replaceAll('-', ':').toUpperCase();
  if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(value)) {
    throw const FormatException(
      'Nhập đủ 6 cặp ký tự, ví dụ A4:BB:6D:12:34:56.',
    );
  }
  final bytes = value.split(':').map((v) => int.parse(v, radix: 16)).toList();
  if (bytes.every((b) => b == 0) || bytes[0] & 1 != 0) {
    throw const FormatException('Cần địa chỉ MAC của card mạng máy tính.');
  }
  return value;
}

int ipv4Number(String input) {
  final parts = input.split('.');
  if (parts.length != 4 ||
      parts.any(
        (p) => !RegExp(r'^\d{1,3}$').hasMatch(p) || int.parse(p) > 255,
      )) {
    throw const FormatException('Địa chỉ IPv4 không hợp lệ.');
  }
  return parts.fold(0, (value, part) => (value << 8) | int.parse(part));
}

String ipv4String(int value) =>
    [24, 16, 8, 0].map((shift) => (value >> shift) & 255).join('.');

class Lan {
  final String ip, mask;
  Lan(this.ip, this.mask) {
    ipv4Number(ip);
    final inverse = (~ipv4Number(mask)) & 0xffffffff;
    if ((inverse & (inverse + 1)) != 0) {
      throw const FormatException('Subnet không hợp lệ.');
    }
  }
  int get network => ipv4Number(ip) & ipv4Number(mask);
  int get end => network | ((~ipv4Number(mask)) & 0xffffffff);
  String get broadcast => ipv4String(end);
  String get key => '${ipv4String(network)}/$mask';
  bool contains(String address) =>
      (ipv4Number(address) & ipv4Number(mask)) == network;
  List<String> get hosts {
    final start = end - network > 255 ? ipv4Number(ip) & 0xffffff00 : network;
    final last = end - network > 255 ? start + 255 : end;
    return [
      for (var n = start + 1; n < last; n++)
        if (ipv4String(n) != ip) ipv4String(n),
    ];
  }
}

Uint8List magicPacket(String mac) {
  final bytes = normalizeMac(mac)
      .split(':')
      .map((v) => int.parse(v, radix: 16))
      .toList();
  return Uint8List.fromList([
    ...List.filled(6, 255),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

class Pc {
  final String id, name, mac, ip, broadcast, network;
  final int port, retries, timeout;
  final bool favorite;
  final bool agentPaired;
  final DateTime? lastWake;
  const Pc({
    required this.id,
    required this.name,
    required this.mac,
    this.ip = '',
    this.broadcast = '',
    this.network = '',
    this.port = 9,
    this.retries = 3,
    this.timeout = 60,
    this.favorite = false,
    this.agentPaired = false,
    this.lastWake,
  });
  Pc copy({
    bool? favorite,
    DateTime? lastWake,
    bool? agentPaired,
    String? ip,
  }) => Pc(
    id: id,
    name: name,
    mac: mac,
    ip: ip ?? this.ip,
    broadcast: broadcast,
    network: network,
    port: port,
    retries: retries,
    timeout: timeout,
    favorite: favorite ?? this.favorite,
    agentPaired: agentPaired ?? this.agentPaired,
    lastWake: lastWake ?? this.lastWake,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mac': mac,
    'ip': ip,
    'broadcast': broadcast,
    'network': network,
    'port': port,
    'retries': retries,
    'timeout': timeout,
    'favorite': favorite,
    'agentPaired': agentPaired,
    'lastWake': lastWake?.toIso8601String(),
  };
  factory Pc.fromJson(Map<String, dynamic> j) => Pc(
    id: j['id'],
    name: j['name'],
    mac: normalizeMac(j['mac']),
    ip: j['ip'] ?? '',
    broadcast: j['broadcast'] ?? '',
    network: j['network'] ?? '',
    port: j['port'] ?? 9,
    retries: j['retries'] ?? 3,
    timeout: j['timeout'] ?? 60,
    favorite: j['favorite'] ?? false,
    agentPaired: j['agentPaired'] ?? false,
    lastWake: DateTime.tryParse(j['lastWake'] ?? ''),
  );
}

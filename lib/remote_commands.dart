import 'dart:convert';

String textCommand(String text) {
  final bytes = utf8.encode(text);
  if (bytes.isEmpty ||
      bytes.length > 240 ||
      text.runes.any((c) => c < 32 || (c >= 127 && c <= 159))) {
    throw const FormatException(
      'Mỗi lần gửi tối đa 240 byte UTF-8, không chứa ký tự điều khiển. Hãy chia đoạn ngắn hơn.',
    );
  }
  return 'text:${base64Encode(bytes)}';
}

String keyCommand(String label, Iterable<String> modifiers) {
  const keys = {
    'Esc': 27,
    'Tab': 9,
    'Enter': 13,
    'Backspace': 8,
    'Delete': 46,
    'Space': 32,
    '←': 37,
    '↑': 38,
    '→': 39,
    '↓': 40,
  };
  final key =
      keys[label] ??
      (RegExp(r'^F([1-9]|1[0-2])$').hasMatch(label)
          ? 111 + int.parse(label.substring(1))
          : RegExp(r'^[A-Z0-9]$').hasMatch(label)
          ? label.codeUnitAt(0)
          : null);
  if (key == null) throw const FormatException('Phím chưa được hỗ trợ.');
  const masks = {'Ctrl': 1, 'Alt': 2, 'Shift': 4, 'Win': 8};
  final mask = modifiers.fold(0, (value, mod) => value | (masks[mod] ?? 0));
  return 'key:$mask:$key';
}

const quickCommands = {
  'Desktop': 'key:8:68',
  'Đổi cửa sổ': 'key:2:9',
  'Chụp màn hình': 'key:12:83',
  'Tìm kiếm': 'key:8:83',
  'Bài trước': 'key:0:177',
  'Bài sau': 'key:0:176',
  'Phát': 'key:0:179',
  'Tạm dừng': 'key:0:179',
  'Tắt tiếng': 'key:0:173',
  'Bật tiếng': 'key:0:173',
  'Giảm âm lượng': 'key:0:174',
  'Tăng âm lượng': 'key:0:175',
};

bool validInputCommand(String command) {
  if (command.startsWith('text:')) {
    try {
      return textCommand(utf8.decode(base64Decode(command.substring(5)))) ==
          command;
    } catch (_) {
      return false;
    }
  }
  final m = RegExp(r'^key:(\d{1,2}):(\d{1,3})$').firstMatch(command);
  if (m == null || int.parse(m[1]!) > 15) return false;
  final k = int.parse(m[2]!);
  return (k >= 48 && k <= 90) ||
      (k >= 112 && k <= 123) ||
      (k >= 173 && k <= 179) ||
      [8, 9, 13, 27, 32, 37, 38, 39, 40, 46].contains(k);
}

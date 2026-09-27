import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/remote_commands.dart';

void main() {
  test('Unicode text, shortcuts and media produce bounded commands', () {
    final command = textCommand('Xin chào 👋');
    expect(utf8.decode(base64Decode(command.substring(5))), 'Xin chào 👋');
    expect(validInputCommand(command), isTrue);
    expect(keyCommand('C', ['Ctrl']), 'key:1:67');
    expect(keyCommand('F12', ['Alt', 'Shift']), 'key:6:123');
    expect(quickCommands.values.every(validInputCommand), isTrue);
  });
  test(
    'rejects overlong text, controls and commands outside the allowlist',
    () {
      expect(() => textCommand('a' * 241), throwsFormatException);
      expect(() => textCommand('a\nb'), throwsFormatException);
      for (final command in [
        'key:16:67',
        'key:0:255',
        'key:0:16',
        'text:@@@@',
        'shell:cmd',
      ]) {
        expect(validInputCommand(command), isFalse);
      }
    },
  );
}

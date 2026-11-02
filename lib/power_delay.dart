const defaultPowerDelay = 10;
const maxPowerDelay = 86400;

bool validPowerDelay(int seconds) => seconds >= 1 && seconds <= maxPowerDelay;

bool validPowerDelayCommand(String command) {
  final match = RegExp(r'^power:(sleep|shutdown):([1-9][0-9]{0,4})$')
      .firstMatch(command);
  return match != null && validPowerDelay(int.parse(match[2]!));
}

String powerDelayCommand(String action, int seconds) {
  if (!{'sleep', 'shutdown'}.contains(action) || !validPowerDelay(seconds)) {
    throw ArgumentError('Thời gian chờ không hợp lệ.');
  }
  // Keep the original command compatible with Agents using the default delay.
  return seconds == defaultPowerDelay ? action : 'power:$action:$seconds';
}

String powerDelayLabel(int seconds) {
  if (seconds % 3600 == 0) return '${seconds ~/ 3600} giờ';
  if (seconds % 60 == 0) return '${seconds ~/ 60} phút';
  return '$seconds giây';
}

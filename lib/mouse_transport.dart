import 'dart:async';
import 'dart:collection';
import 'dart:math';

bool validMouseCommand(String command) {
  final p = command.split(':');
  if (p.length < 3 ||
      p[0] != 'mouse' ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(p[1]))
    return false;
  if (p.length == 3)
    return {'left', 'right', 'down', 'up', 'hold'}.contains(p[2]);
  bool bounded(String s, int limit) {
    final n = int.tryParse(s);
    return n != null && n >= -limit && n <= limit;
  }

  return (p.length == 5 &&
          p[2] == 'move' &&
          bounded(p[3], 512) &&
          bounded(p[4], 512)) ||
      (p.length == 4 && p[2] == 'wheel' && bounded(p[3], 1200));
}

class _MouseEvent {
  final String action;
  double x, y;
  final Completer<bool>? done;
  _MouseEvent(this.action, {this.x = 0, this.y = 0, this.done});
}

/// Bounded, ordered transport. Only adjacent motion events may be coalesced.
class MouseTransport {
  final Future<String> Function(String) send;
  final void Function() onError;
  final String session = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final _queue = Queue<_MouseEvent>();
  Timer? _pump, _heartbeat;
  bool _busy = false, _closed = false, _held = false;
  MouseTransport({required this.send, required this.onError});

  void move(double x, double y) => _add(_MouseEvent('move', x: x, y: y));
  void wheel(double delta) => _add(_MouseEvent('wheel', x: -delta * 6));
  void click(bool right) => _add(_MouseEvent(right ? 'right' : 'left'));
  Future<bool> drag(bool hold) {
    _heartbeat?.cancel();
    _held = hold;
    final result = Completer<bool>();
    _add(_MouseEvent(hold ? 'down' : 'up', done: result));
    if (hold) {
      _heartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (_held && !_queue.any((e) => e.action == 'hold'))
          _add(_MouseEvent('hold'));
      });
    }
    return result.future;
  }

  void _add(_MouseEvent event) {
    if (_closed) {
      event.done?.complete(false);
      return;
    }
    if (_queue.isNotEmpty &&
        (event.action == 'move' || event.action == 'wheel') &&
        _queue.last.action == event.action) {
      _queue.last.x = (_queue.last.x + event.x).clamp(-512, 512);
      _queue.last.y = (_queue.last.y + event.y).clamp(-512, 512);
    } else {
      if (_queue.length >= 24) {
        event.done?.complete(false);
        release();
        onError();
        return;
      }
      _queue.add(event);
    }
    _pump ??= Timer(const Duration(milliseconds: 25), () {
      _pump = null;
      _drain();
    });
  }

  void _clear() {
    for (final e in _queue) {
      if (!(e.done?.isCompleted ?? true)) e.done!.complete(false);
    }
    _queue.clear();
  }

  void _fail() {
    _held = false;
    _heartbeat?.cancel();
    _clear();
    // Best effort release; the Windows lease is the fallback if networking fails.
    send('mouse:$session:up').catchError((_) => 'input_failed');
    if (!_closed) onError();
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final e = _queue.removeFirst();
        final x = e.x.round().clamp(
          e.action == 'wheel' ? -1200 : -512,
          e.action == 'wheel' ? 1200 : 512,
        );
        final y = e.y.round().clamp(-512, 512);
        final suffix = e.action == 'move'
            ? 'move:$x:$y'
            : e.action == 'wheel'
            ? 'wheel:$x'
            : e.action;
        try {
          final result = await send('mouse:$session:$suffix');
          final ok = result == 'input_ok';
          if (!(e.done?.isCompleted ?? true)) e.done!.complete(ok);
          if (!ok) {
            _fail();
            break;
          }
        } catch (_) {
          if (!(e.done?.isCompleted ?? true)) e.done!.complete(false);
          _fail();
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<bool> release() {
    _held = false;
    _heartbeat?.cancel();
    _clear();
    final done = Completer<bool>();
    _add(_MouseEvent('up', done: done));
    return done.future;
  }

  void dispose() {
    if (_closed) return;
    release();
    _closed = true;
    // The queued release drains after any in-flight request, without retrying motion.
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

class SnapshotEncoder {
  static const _threshold = 32 * 1024;

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _errors;
  Completer<SendPort>? _starting;
  final Map<int, Completer<String>> _pending = {};
  int _next = 0;
  bool _disposed = false;

  static int _weight(Map<String, Object> values) {
    var total = 0;
    for (final value in values.values) {
      total += value is String ? value.length : 8;
    }
    return total;
  }

  static void _serve(SendPort ready) {
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((message) {
      final request = message as List<Object?>;
      final reply = request[1] as SendPort;
      try {
        reply.send([
          request[0],
          jsonEncode({'version': 1, 'values': request[2]}),
        ]);
      } catch (error) {
        reply.send([request[0], null, error.toString()]);
      }
    });
  }

  Future<SendPort> _channel() async {
    final port = _requests;
    if (port != null) return port;
    final starting = _starting;
    if (starting != null) return starting.future;
    final completer = Completer<SendPort>();
    _starting = completer;
    try {
      final responses = ReceivePort();
      final isolate = await Isolate.spawn(
        _serve,
        responses.sendPort,
        errorsAreFatal: false,
      );
      _isolate = isolate;
      _responses = responses;
      _errors = responses.listen((message) {
        if (message is SendPort) {
          if (!completer.isCompleted) completer.complete(message);
          return;
        }
        final reply = message as List<Object?>;
        final pending = _pending.remove(reply[0]);
        if (pending == null) return;
        final content = reply[1] as String?;
        if (content == null) {
          pending.completeError(StateError('本地配置编码失败'));
        } else {
          pending.complete(content);
        }
      });
      isolate.addErrorListener(responses.sendPort);
      final ready = await completer.future;
      _requests = ready;
      return ready;
    } catch (_) {
      _reset();
      rethrow;
    } finally {
      _starting = null;
    }
  }

  void _reset() {
    _requests = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _responses?.close();
    _responses = null;
    _errors?.cancel();
    _errors = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('本地配置编码中断'));
      }
    }
    _pending.clear();
  }

  Future<String> encode(Map<String, Object> values) async {
    if (_disposed || _weight(values) < _threshold) {
      return jsonEncode({'version': 1, 'values': values});
    }
    try {
      final port = await _channel();
      final id = _next++;
      final completer = Completer<String>();
      _pending[id] = completer;
      port.send([id, _responses!.sendPort, values]);
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pending.remove(id);
          throw StateError('本地配置编码超时');
        },
      );
    } catch (_) {
      return jsonEncode({'version': 1, 'values': values});
    }
  }

  void dispose() {
    _disposed = true;
    _reset();
  }
}

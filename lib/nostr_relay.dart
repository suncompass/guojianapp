import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'nostr_crypto.dart';

/// nostr relay 连接状态，供界面显示「已连接 N/M」。
class RelayState {
  static const idle = '未连接';
  static const connecting = '连接中';
  static const connected = '已连接';
  static const closed = '已断开';
  static const failed = '连接失败';
}

class NostrRelayPool {
  NostrRelayPool(
    this.relays, {
    required this.onEvent,
    this.onStatus,
    this.onNotice,
  });

  final List<String> relays;
  final void Function(NostrEvent event) onEvent;
  final void Function()? onStatus;
  final void Function(String message)? onNotice;

  static const subscriptionLimit = 500;
  static const backfillRounds = 4;
  static const connectTimeout = Duration(seconds: 12);
  static const publishTimeout = Duration(seconds: 8);

  final _links = <_RelayLink>[];
  var _closed = false;
  var _started = false;
  var _subscription = 'zhenguo-feed';

  int get connected =>
      _links.where((link) => link.socket != null).length;

  int get total => _links.length;

  Map<String, String> get states => {
    for (final link in _links) link.url: link.state,
  };

  void start({
    required int kind,
    required String dTag,
    String subscription = 'zhenguo-feed',
  }) {
    if (_closed) return;
    _subscription = subscription;
    if (!_started) {
      _started = true;
      for (final url in relays) {
        final link = _RelayLink(url, this, kind: kind, dTag: dTag);
        _links.add(link);
        link.connect();
      }
    } else {
      for (final link in _links) {
        link.kind = kind;
        link.dTag = dTag;
        link.subscribe();
      }
    }
    _notify();
  }

  Future<int> publish(NostrEvent event) async {
    if (_closed || _links.isEmpty) return 0;
    final payload = jsonEncode(['EVENT', event.toJson()]);
    final results = await Future.wait(
      _links.map((link) => link.send(payload, event.id)),
    );
    return results.where((accepted) => accepted).length;
  }

  Future<void> dispose() async {
    _closed = true;
    for (final link in _links) {
      await link.close();
    }
    _links.clear();
  }

  void _notify() {
    if (_closed) return;
    onStatus?.call();
  }

  void _received(NostrEvent event) => onEvent(event);

  void _notice(String message) => onNotice?.call(message);
}

class _RelayLink {
  _RelayLink(this.url, this.owner, {required this.kind, required this.dTag});

  final String url;
  final NostrRelayPool owner;
  int kind;
  String dTag;
  WebSocket? socket;
  String state = RelayState.idle;
  int _retries = 0;
  int _round = 0;
  int _received = 0;
  int _oldest = 0;
  Timer? _retry;
  Timer? _closeSubscription;
  final _pending = <String, Completer<bool>>{};

  Future<void> connect() async {
    if (socket != null) return;
    state = RelayState.connecting;
    owner._notify();
    try {
      final webSocket = await WebSocket.connect(
        url,
      ).timeout(NostrRelayPool.connectTimeout);
      socket = webSocket;
      state = RelayState.connected;
      _retries = 0;
      _round = 0;
      _received = 0;
      _oldest = 0;
      webSocket.listen(
        _onMessage,
        onError: (Object _) => _onClosed(RelayState.failed),
        onDone: () => _onClosed(RelayState.closed),
        cancelOnError: true,
      );
      _subscribe();
      owner._notify();
    } catch (_) {
      _onClosed(RelayState.failed);
    }
  }

  void subscribe() {
    if (socket == null) {
      connect();
      return;
    }
    _round = 0;
    _received = 0;
    _oldest = 0;
    _subscribe();
  }

  void _subscribe() {
    _sendRaw([
      'REQ',
      owner._subscription,
      {
        'kinds': [kind],
        '#d': [dTag],
        'limit': NostrRelayPool.subscriptionLimit,
      },
    ]);
  }

  Future<bool> send(String payload, String eventId) async {
    final webSocket = socket;
    if (webSocket == null) return false;
    final completer = Completer<bool>();
    _pending[eventId] = completer;
    try {
      webSocket.add(payload);
    } catch (_) {
      _pending.remove(eventId);
      return false;
    }
    return completer.future.timeout(
      NostrRelayPool.publishTimeout,
      onTimeout: () {
        _pending.remove(eventId);
        return false;
      },
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Object? payload;
    try {
      payload = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (payload is! List || payload.isEmpty) return;
    final type = '${payload.first}';
    if (type == 'EVENT' && payload.length >= 3) {
      final event = NostrEvent.fromRelay(payload[2]);
      if (event == null || event.id.isEmpty) return;
      _received++;
      if (_oldest == 0 || event.createdAt < _oldest) {
        _oldest = event.createdAt;
      }
      owner._received(event);
      return;
    }
    if (type == 'EOSE') {
      _backfill();
      return;
    }
    if (type == 'OK' && payload.length >= 2) {
      final completer = _pending.remove('${payload[1]}');
      completer?.complete(payload.length >= 3 && payload[2] == true);
      return;
    }
    if (type == 'NOTICE' && payload.length >= 2) {
      owner._notice('$url ${payload[1]}');
      return;
    }
    if (type == 'CLOSED' && payload.length >= 2) {
      state = RelayState.closed;
      owner._notify();
    }
  }

  void _backfill() {
    if (_round >= NostrRelayPool.backfillRounds) return;
    if (_received < NostrRelayPool.subscriptionLimit || _oldest <= 0) return;
    _round++;
    _received = 0;
    final subscription = '${owner._subscription}-$url-$_round';
    _sendRaw([
      'REQ',
      subscription,
      {
        'kinds': [kind],
        '#d': [dTag],
        'until': _oldest - 1,
        'limit': NostrRelayPool.subscriptionLimit,
      },
    ]);
    _closeSubscription?.cancel();
    _closeSubscription = Timer(const Duration(seconds: 20), () {
      _sendRaw(['CLOSE', subscription]);
    });
  }

  void _sendRaw(Object payload) {
    final webSocket = socket;
    if (webSocket == null) return;
    try {
      webSocket.add(jsonEncode(payload));
    } catch (_) {
      _onClosed(RelayState.failed);
    }
  }

  void _onClosed(String status) {
    state = status;
    socket = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pending.clear();
    if (owner._closed) return;
    owner._notify();
    _retry?.cancel();
    final delay = Duration(
      milliseconds:
          (2000 * (1 << _retries.clamp(0, 4))).clamp(2000, 30000).toInt(),
    );
    _retries++;
    _retry = Timer(delay, connect);
  }

  Future<void> close() async {
    _retry?.cancel();
    _closeSubscription?.cancel();
    final webSocket = socket;
    socket = null;
    if (webSocket != null) {
      try {
        await webSocket.close();
      } catch (_) {}
    }
  }
}

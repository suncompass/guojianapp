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
  // 生产接收路径只向业务层交付通过哈希、签名和订阅校验的事件。
  final void Function(NostrEvent event) onEvent;
  final void Function()? onStatus;
  final void Function(String message)? onNotice;

  static const subscriptionLimit = 500;
  static const backfillRounds = 4;
  static const connectTimeout = Duration(seconds: 12);
  static const publishTimeout = Duration(seconds: 8);
  static const maxMessageBytes = 1024 * 1024;
  static const maxPendingMessages = 512;
  static const maxPendingBytes = 8 * 1024 * 1024;

  final _links = <_RelayLink>[];
  var _closed = false;
  var _started = false;
  var _subscription = 'zhenguo-feed';

  int get connected => _links.where((link) => link.socket != null).length;
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
    if (!_closed) onStatus?.call();
  }

  void _received(NostrEvent event) {
    if (!_closed) onEvent(event);
  }

  void _notice(String message) {
    if (!_closed) onNotice?.call(message);
  }
}

class _RelaySubscription {
  _RelaySubscription(this.id, this.round);

  final String id;
  final int round;
  final ids = <String>{};
  int oldest = 0;
  bool ended = false;
  Timer? timeout;
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
  int _generation = 0;
  bool _connecting = false;
  bool _closed = false;
  Timer? _retry;
  final _subscriptions = <String, _RelaySubscription>{};
  final _pending = <String, Completer<bool>>{};
  Future<void> _incoming = Future<void>.value();
  int _queuedMessages = 0;
  int _queuedBytes = 0;

  Future<void> connect() async {
    if (_closed || owner._closed || socket != null || _connecting) return;
    _connecting = true;
    state = RelayState.connecting;
    owner._notify();
    try {
      final webSocket = await WebSocket.connect(
        url,
      ).timeout(NostrRelayPool.connectTimeout);
      if (_closed || owner._closed) {
        await webSocket.close();
        return;
      }
      socket = webSocket;
      state = RelayState.connected;
      _retries = 0;
      webSocket.listen(
        (raw) {
          if (identical(socket, webSocket)) _onMessage(raw);
        },
        onError: (Object _) {
          if (identical(socket, webSocket)) _onClosed(RelayState.failed);
        },
        onDone: () {
          if (identical(socket, webSocket)) _onClosed(RelayState.closed);
        },
        cancelOnError: true,
      );
      subscribe();
      owner._notify();
    } catch (_) {
      if (!_closed && !owner._closed) _onClosed(RelayState.failed);
    } finally {
      _connecting = false;
    }
  }

  void subscribe() {
    if (_closed || owner._closed) return;
    if (socket == null) {
      connect();
      return;
    }
    _clearSubscriptions(sendClose: true);
    _generation++;
    _subscribe(0);
  }

  void _subscribe(int round, {int? until}) {
    final id = '${owner._subscription}-$_generation-$round';
    final subscription = _RelaySubscription(id, round);
    _subscriptions[id] = subscription;
    _sendRaw([
      'REQ',
      id,
      {
        'kinds': [kind],
        '#d': [dTag],
        'limit': NostrRelayPool.subscriptionLimit,
        'until': ?until,
      },
    ]);
    if (round > 0 && identical(_subscriptions[id], subscription)) {
      subscription.timeout = Timer(const Duration(seconds: 20), () {
        if (!identical(_subscriptions[id], subscription)) return;
        _subscriptions.remove(id);
        _sendRaw(['CLOSE', id]);
      });
    }
  }

  Future<bool> send(String payload, String eventId) async {
    final webSocket = socket;
    if (_closed || webSocket == null) return false;
    final existing = _pending[eventId];
    if (existing != null) return existing.future;
    final completer = Completer<bool>();
    _pending[eventId] = completer;
    try {
      webSocket.add(payload);
    } catch (_) {
      _pending.remove(eventId);
      completer.complete(false);
    }
    return completer.future.timeout(
      NostrRelayPool.publishTimeout,
      onTimeout: () {
        if (identical(_pending[eventId], completer)) _pending.remove(eventId);
        if (!completer.isCompleted) completer.complete(false);
        return false;
      },
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    if (raw.length > NostrRelayPool.maxMessageBytes) {
      _overloaded();
      return;
    }
    final bytes = utf8.encode(raw).length;
    if (bytes > NostrRelayPool.maxMessageBytes) {
      _overloaded();
      return;
    }
    final Object? payload;
    try {
      payload = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (payload is! List || payload.isEmpty) return;
    final type = payload.first;
    if (type == 'OK' && payload.length >= 3) {
      final completer = _pending.remove(payload[1]);
      completer?.complete(payload[2] == true);
      return;
    }
    if (type == 'NOTICE' && payload.length >= 2 && payload[1] is String) {
      final message = payload[1] as String;
      owner._notice(
        '$url ${message.substring(0, message.length > 600 ? 600 : message.length)}',
      );
      return;
    }
    if (payload.length < 2 || payload[1] is! String) return;
    final subscription = _subscriptions[payload[1]];
    if (subscription == null) return;
    if (type == 'EVENT' && payload.length == 3) {
      final event = NostrEvent.fromRelay(payload[2]);
      if (event == null ||
          event.kind != kind ||
          event.tagValue('d') != dTag ||
          event.tags.where((tag) => tag.first == 'd').length != 1) {
        return;
      }
      _enqueue(bytes, subscription, () async {
        if (!await verifyNostrEventAsync(event) || !_current(subscription)) {
          return;
        }
        // EOSE 之前的有效事件才参与历史游标，重复与伪造事件不能推进游标。
        if (!subscription.ended &&
            subscription.ids.length < NostrRelayPool.subscriptionLimit &&
            subscription.ids.add(event.id)) {
          if (subscription.oldest == 0 ||
              event.createdAt < subscription.oldest) {
            subscription.oldest = event.createdAt;
          }
        }
        owner._received(event);
      });
    } else if (type == 'EOSE' && payload.length == 2) {
      // 排在此前 EVENT 的验证之后，不能让先到的 EOSE 越过后台验签。
      subscription.timeout?.cancel();
      _enqueue(0, subscription, () async => _backfill(subscription));
    } else if (type == 'CLOSED') {
      subscription.timeout?.cancel();
      _subscriptions.remove(subscription.id);
      if (subscription.round == 0) _onClosed(RelayState.closed);
    }
  }

  bool _current(_RelaySubscription subscription) =>
      !_closed &&
      !owner._closed &&
      identical(_subscriptions[subscription.id], subscription);

  void _enqueue(
    int bytes,
    _RelaySubscription subscription,
    Future<void> Function() operation,
  ) {
    if (_queuedMessages >= NostrRelayPool.maxPendingMessages ||
        _queuedBytes + bytes > NostrRelayPool.maxPendingBytes) {
      _overloaded();
      return;
    }
    _queuedMessages++;
    _queuedBytes += bytes;
    // 每个 relay 同时最多一次验签；计数与字节双上限限制等待队列。
    // OK 回执不走此队列，避免历史回填拖延本机发布确认。
    _incoming = _incoming.then((_) async {
      try {
        if (_current(subscription)) await operation();
      } catch (_) {
        if (_current(subscription)) owner._notice('$url 事件验证失败，已忽略');
      } finally {
        _queuedMessages--;
        _queuedBytes -= bytes;
      }
    });
  }

  void _backfill(_RelaySubscription subscription) {
    if (subscription.ended) return;
    subscription.ended = true;
    subscription.timeout?.cancel();
    if (subscription.round > 0) {
      _subscriptions.remove(subscription.id);
      _sendRaw(['CLOSE', subscription.id]);
    }
    if (socket == null ||
        subscription.round >= NostrRelayPool.backfillRounds ||
        subscription.ids.length < NostrRelayPool.subscriptionLimit ||
        subscription.oldest <= 0) {
      return;
    }
    _subscribe(subscription.round + 1, until: subscription.oldest - 1);
  }

  void _overloaded() {
    owner._notice('$url 消息超出安全上限，已断开并稍后重连');
    _onClosed(RelayState.failed);
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

  void _clearSubscriptions({bool sendClose = false}) {
    final subscriptions = _subscriptions.values.toList();
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription.timeout?.cancel();
      if (sendClose) _sendRaw(['CLOSE', subscription.id]);
    }
  }

  void _onClosed(String status) {
    state = status;
    final webSocket = socket;
    socket = null;
    _clearSubscriptions();
    if (webSocket != null) {
      unawaited(webSocket.close().catchError((Object _) {}));
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pending.clear();
    if (_closed || owner._closed) return;
    owner._notify();
    _retry?.cancel();
    final delay = Duration(
      milliseconds: (2000 * (1 << _retries.clamp(0, 4)))
          .clamp(2000, 30000)
          .toInt(),
    );
    _retries++;
    _retry = Timer(delay, connect);
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _onClosed(RelayState.closed);
  }
}

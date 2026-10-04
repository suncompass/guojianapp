import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/nostr_crypto.dart';
import 'package:duanju_app/nostr_relay.dart';
import 'package:flutter_test/flutter_test.dart';

const _tag = 'zhenguo:app:recommend:v1';
const _secret =
    '0000000000000000000000000000000000000000000000000000000000000003';

NostrEvent _event({int offset = 0, int kind = 30078}) => NostrIdentity.sign(
  kind: kind,
  createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + offset,
  tags: [
    ['d', _tag],
  ],
  content: '{"v":1,"i":[]}',
  secretHex: _secret,
);

class _Request {
  _Request(this.socket, this.message);
  final WebSocket socket;
  final List<dynamic> message;
  String get subscription => message[1] as String;
  void event(NostrEvent value, {String? subscription}) => socket.add(
    jsonEncode(['EVENT', subscription ?? this.subscription, value.toJson()]),
  );
}

void main() {
  late HttpServer server;
  late NostrRelayPool pool;
  late StreamController<_Request> requests;
  late List<WebSocket> sockets;
  late List<NostrEvent> received;
  late StreamController<NostrEvent> events;

  Future<_Request> next(String type) => requests.stream
      .firstWhere((request) => request.message.first == type)
      .timeout(const Duration(seconds: 10));

  Future<_Request> start() async {
    final request = next('REQ');
    pool.start(kind: 30078, dTag: _tag);
    return request;
  }

  setUp(() async {
    sockets = [];
    received = [];
    requests = StreamController<_Request>.broadcast();
    events = StreamController<NostrEvent>.broadcast();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        requests.add(_Request(socket, jsonDecode(raw as String) as List));
      });
    });
    pool = NostrRelayPool(
      ['ws://127.0.0.1:${server.port}'],
      onEvent: (event) {
        received.add(event);
        events.add(event);
      },
    );
  });

  tearDown(() async {
    await pool.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
    await requests.close();
    await events.close();
  });

  test('只交付当前订阅中通过验签的事件', () async {
    final request = await start();
    final valid = _event();
    final delivered = events.stream.first.timeout(const Duration(seconds: 10));
    request.event(valid, subscription: 'unrequested');
    request.socket.add(
      jsonEncode([
        'EVENT',
        request.subscription,
        {...valid.toJson(), 'sig': '0' * 128},
      ]),
    );
    request.socket.add(
      jsonEncode([
        'EVENT',
        request.subscription,
        {...valid.toJson(), 'content': 'forged'},
      ]),
    );
    request.event(_event(offset: 3600));
    request.event(_event(kind: 1));
    request.event(valid);
    expect((await delivered).id, valid.id);
    expect(received.map((event) => event.id), [valid.id]);
  });

  test('刷新后旧订阅和旧 EOSE 不影响新订阅', () async {
    final old = await start();
    final refreshed = next('REQ');
    pool.start(kind: 30078, dTag: _tag);
    final current = await refreshed;
    expect(current.subscription, isNot(old.subscription));
    final delivered = events.stream.first.timeout(const Duration(seconds: 10));
    old.event(_event(offset: -2));
    old.socket.add(jsonEncode(['EOSE', old.subscription]));
    final valid = _event(offset: -1);
    current.event(valid);
    expect((await delivered).id, valid.id);
    expect(received, hasLength(1));
  });

  test('EOSE 等待之前的验签完成且不关闭实时订阅', () async {
    final request = await start();
    final delivered = events.stream
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 10));
    final first = _event(offset: -2);
    final second = _event(offset: -1);
    request.event(first);
    request.socket.add(jsonEncode(['EOSE', request.subscription]));
    request.event(second);
    expect((await delivered).map((event) => event.id), [first.id, second.id]);
  });

  test('超大消息断开连接且不交付事件', () async {
    final request = await start();
    final closed = Completer<void>();
    // 新建观察流不允许重复 listen；由客户端连接状态判断断开。
    request.socket.add('x' * (NostrRelayPool.maxMessageBytes + 1));
    final timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (pool.connected == 0 && !closed.isCompleted) closed.complete();
    });
    try {
      await closed.future.timeout(const Duration(seconds: 5));
    } finally {
      timer.cancel();
    }
    expect(received, isEmpty);
  });

  test('发布确认不等待历史事件验签队列', () async {
    final request = await start();
    final incoming = _event(offset: -1);
    for (var index = 0; index < 20; index++) {
      request.event(incoming);
    }
    final outbound = next('EVENT');
    final event = _event();
    final accepted = pool.publish(event);
    final sent = await outbound;
    sent.socket.add(jsonEncode(['OK', event.id, true, 'saved']));
    expect(await accepted.timeout(const Duration(seconds: 5)), 1);
  });

  test('销毁后在途验签不得回调业务层', () async {
    final request = await start();
    request.event(_event());
    await pool.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(received, isEmpty);
  });
}

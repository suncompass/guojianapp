import 'dart:io';

import 'package:duanju_app/nostr_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret =
    '0000000000000000000000000000000000000000000000000000000000000003';
const _now = 1790000000;

NostrEvent _event({int createdAt = _now}) => NostrIdentity.sign(
  kind: 30078,
  createdAt: createdAt,
  tags: [
    ['d', 'zhenguo:app:recommend:v1'],
  ],
  content: '{"v":1,"i":[]}',
  secretHex: _secret,
);

void main() {
  // bitcoin/bips bip-0340/test-vectors.csv 的 0..14；Nostr 消息固定为 32 字节。
  final vectors = File('test/fixtures/bip340.csv').readAsLinesSync().skip(1);
  for (final line in vectors) {
    final row = line.split(',');
    test('BIP-340 官方验证向量 ${row[0]}', () {
      expect(
        verifySchnorrSignature(
          publicKey: row[1].toLowerCase(),
          message: row[2].toLowerCase(),
          signature: row[3].toLowerCase(),
        ),
        row[4] == 'TRUE',
      );
    });
  }

  test('正常事件与空列表撤回均通过哈希和签名验证', () {
    expect(verifyNostrEvent(_event(), nowSeconds: _now), isTrue);
  });

  test('篡改内容、事件 ID、签名、公钥或标签均被拒绝', () {
    final original = _event().toJson();
    for (final mutation in <Map<String, dynamic>>[
      {'content': '{"v":1,"i":[["forged"]]}'},
      {'id': 'f' * 64},
      {'sig': '0' * 128},
      {'pubkey': 'a' * 64},
      {
        'tags': [
          ['d', 'different'],
        ],
      },
    ]) {
      final event = NostrEvent.fromRelay({
        ...original,
        ...mutation,
      }, nowSeconds: _now);
      expect(event, isNotNull);
      expect(verifyNostrEvent(event!, nowSeconds: _now), isFalse);
    }
  });

  test('重算被篡改事件的 ID 仍不能绕过签名', () {
    final original = _event();
    final forged = NostrEvent(
      id: eventId(
        pubkey: original.pubkey,
        createdAt: original.createdAt,
        kind: original.kind,
        tags: original.tags,
        content: 'forged',
      ),
      pubkey: original.pubkey,
      createdAt: original.createdAt,
      kind: original.kind,
      tags: original.tags,
      content: 'forged',
      sig: original.sig,
    );
    expect(verifyNostrEvent(forged, nowSeconds: _now), isFalse);
  });

  test('结构检查不强制转换字符串、浮点数或标签对象', () {
    final original = _event().toJson();
    for (final mutation in <Map<String, dynamic>>[
      {'created_at': '1790000000'},
      {'created_at': 1790000000.5},
      {'created_at': 0},
      {'kind': 30078.0},
      {'kind': -1},
      {'pubkey': 'z' * 64},
      {'sig': ''},
      {'content': <String, dynamic>{}},
      {'tags': 'invalid'},
      {
        'tags': [
          ['d', 42],
        ],
      },
      {
        'tags': List.filled(NostrEvent.maxTags + 1, ['d', 'x']),
      },
      {
        'tags': [List.filled(NostrEvent.maxTagValues + 1, 'x')],
      },
      {
        'tags': [
          ['d', 'x' * (NostrEvent.maxTagValueLength + 1)],
        ],
      },
      {'content': 'x' * (NostrEvent.maxContentBytes + 1)},
      {'content': '剧' * (NostrEvent.maxContentBytes ~/ 3 + 1)},
    ]) {
      expect(
        NostrEvent.fromRelay({...original, ...mutation}, nowSeconds: _now),
        isNull,
      );
    }
  });

  test('允许历史回填与五分钟时差，但拒绝更远的未来事件', () {
    expect(verifyNostrEvent(_event(createdAt: 1000), nowSeconds: _now), isTrue);
    final boundary = _now + NostrEvent.futureToleranceSeconds;
    expect(
      verifyNostrEvent(_event(createdAt: boundary), nowSeconds: _now),
      isTrue,
    );
    expect(
      verifyNostrEvent(_event(createdAt: boundary + 1), nowSeconds: _now),
      isFalse,
    );
  });

  test('后台签名和验签可往返', () async {
    final event = await NostrIdentity.signAsync(
      kind: 30078,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      tags: [
        ['d', 'zhenguo:app:recommend:v1'],
      ],
      content: '{"v":1,"i":[]}',
      secretHex: _secret,
    );
    expect(await verifyNostrEventAsync(event), isTrue);
  });
}

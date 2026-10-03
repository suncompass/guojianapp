import 'dart:convert';
import 'dart:typed_data';

import 'package:duanju_app/nostr_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 期望值由参考实现 `../nostr/web/vendor/nostr.bundle.js`（nostr-tools 2.10.4）生成：
/// 固定私钥、固定辅助随机数（全 0）后 `finalizeEvent` 的事件 ID 与签名。
/// 它同时是 BIP-340 官方测试向量中的第 1、2 条（私钥 3 与 b7e15162…）。
const referenceKeys = {
  '0000000000000000000000000000000000000000000000000000000000000003':
      'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
  'b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef':
      'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
  'c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9':
      'dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8',
};

const referenceEvents = [
  {
    'kind': 30078,
    'created_at': 1760000000,
    'tags': [
      ['d', 'zhenguo:app:recommend:v1'],
      ['t', 'zhenguo-app-recommend'],
      ['client', 'zhenguojian-app'],
    ],
    'content':
        '{"v":1,"i":[["hongguo","hongguo:1","都市逆袭","https://p3-novel.byteimg.com/a.jpg","都市",1760000000]]}',
    'id': '87d2fe2075edc5e5f853c405553b97f2869dc7050ea22d7a5304e32a33b2082f',
    'sig':
        'd83e1c7fd5ac15c17db7d6a9095b703c25fe7c5f4c80244d7386619b9d01a499bc396bfc64175f3b9a1fddfe5866c4856fa47e710f1afc1633ff97332a5fd66f',
  },
  {
    'kind': 30078,
    'created_at': 1760000001,
    'tags': [
      ['d', 'zhenguo:app:recommend:v1'],
      ['t', 'zhenguo-app-recommend'],
    ],
    'content': '{"v":1,"i":[]}',
    'id': '49c150018b44573e53bc942ee6a9184989ff7bb4e3c8f048545b8dae082f3d41',
    'sig':
        'b94024868d647b7d6c05624baa5118688defb6205caba0171bef176beb0d60c11aae796c3f88407ececc333bbc89acaf7adf99b52c02a6cbe811fbd122255b37',
  },
  {
    'kind': 30078,
    'created_at': 1760000002,
    'tags': [
      ['d', 'zhenguo:app:recommend:v1'],
    ],
    'content':
        '{"v":1,"i":[["yaguo","yaguo:9","「测试」剧名 emoji😀","https://img.example.com/p.png","古装",1760000002]]}',
    'id': '616d26c7be8a2df585bd1e73a6949081a6383b3e795e3474cd3e628f9c4bf4ec',
    'sig':
        '84a809b98e144b97c2832a6df5ed6e73910b3e223fdc33532c33ac1005333a19b0c86166ef6febbd51bc8ed6abdc8940fe0daffedf93a81f3aa4bb1fce4c2de4',
  },
];

Uint8List _bytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var index = 0; index < out.length; index++) {
    out[index] = int.parse(
      hex.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return out;
}

void main() {
  test('公钥与参考实现一致', () {
    referenceKeys.forEach((secret, pubkey) {
      expect(NostrIdentity.publicKeyOf(secret), pubkey);
    });
  });

  test('事件 ID 与签名与参考实现逐字节一致', () {
    final secret = referenceKeys.keys.first;
    for (final row in referenceEvents) {
      final event = NostrIdentity.sign(
        kind: row['kind']! as int,
        createdAt: row['created_at']! as int,
        tags: [
          for (final tag in row['tags']! as List)
            [for (final value in tag as List) '$value'],
        ],
        content: row['content']! as String,
        secretHex: secret,
        aux: _bytes('00' * 32),
      );
      expect(event.id, row['id'], reason: '${row['content']}');
      expect(event.sig, row['sig'], reason: '${row['content']}');
    }
  });

  test('事件序列化保留 tag 查询能力', () {
    final secret = referenceKeys.keys.first;
    final event = NostrIdentity.sign(
      kind: 30078,
      createdAt: 1760000000,
      tags: [
        ['d', 'zhenguo:app:recommend:v1'],
        ['client', 'zhenguojian-app'],
      ],
      content: '{"v":1,"i":[]}',
      secretHex: secret,
      aux: _bytes('00' * 32),
    );
    final parsed = NostrEvent.fromRelay(
      jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
    );
    expect(parsed, isNotNull);
    expect(parsed!.tagValue('d'), 'zhenguo:app:recommend:v1');
    expect(parsed.tagValue('缺失'), isNull);
    expect(parsed.createdAt, 1760000000);
    expect(parsed.kind, 30078);
    expect(parsed.pubkey, NostrIdentity.publicKeyOf(secret));
  });

  test('生成的随机身份可用', () {
    final identity = NostrIdentity.generate();
    expect(identity.secretHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(identity.publicKey, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(NostrIdentity.publicKeyOf(identity.secretHex), identity.publicKey);
  });

  test('非法私钥被拒绝', () {
    expect(() => NostrIdentity.publicKeyOf('00'), throwsFormatException);
    expect(
      () => NostrIdentity.publicKeyOf('z' * 64),
      throwsFormatException,
    );
    expect(
      () => NostrIdentity.publicKeyOf(
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      ),
      throwsFormatException,
    );
  });
}

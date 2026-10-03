import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final BigInt _prime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);
final BigInt _order = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);
final BigInt _generatorX = BigInt.parse(
  '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
  radix: 16,
);
final BigInt _generatorY = BigInt.parse(
  '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
  radix: 16,
);

class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  String? tagValue(String name) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag.first == name) return tag[1];
    }
    return null;
  }

  static NostrEvent? fromRelay(Object? raw) {
    if (raw is! Map) return null;
    final tags = <List<String>>[];
    final rawTags = raw['tags'];
    if (rawTags is List) {
      for (final row in rawTags) {
        if (row is List) tags.add([for (final value in row) '$value']);
      }
    }
    final createdAt = raw['created_at'];
    final kind = raw['kind'];
    return NostrEvent(
      id: '${raw['id'] ?? ''}',
      pubkey: '${raw['pubkey'] ?? ''}',
      createdAt: createdAt is num ? createdAt.toInt() : 0,
      kind: kind is num ? kind.toInt() : 0,
      tags: tags,
      content: '${raw['content'] ?? ''}',
      sig: '${raw['sig'] ?? ''}',
    );
  }
}

class NostrIdentity {
  NostrIdentity(this.secretHex) : publicKey = publicKeyOf(secretHex);

  final String secretHex;
  final String publicKey;

  static NostrIdentity generate([Random? random]) {
    final source = random ?? Random.secure();
    while (true) {
      final bytes = Uint8List(32);
      for (var index = 0; index < bytes.length; index++) {
        bytes[index] = source.nextInt(256);
      }
      final value = _bytesToBig(bytes);
      if (value > BigInt.zero && value < _order) {
        return NostrIdentity(_bytesToHex(bytes));
      }
    }
  }

  static String publicKeyOf(String secretHex) {
    final secret = _parseSecret(secretHex);
    final point = _multiplyGenerator(secret);
    return _bytesToHex(_bigToBytes(point.x));
  }

  static NostrEvent sign({
    required int kind,
    required int createdAt,
    required List<List<String>> tags,
    required String content,
    required String secretHex,
    Uint8List? aux,
  }) {
    final secret = _parseSecret(secretHex);
    final point = _multiplyGenerator(secret);
    final publicKey = _bytesToHex(_bigToBytes(point.x));
    final id = eventId(
      pubkey: publicKey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
    );
    final signature = _sign(
      message: _hexToBytes(id),
      secret: secret,
      point: point,
      aux: aux ?? _randomBytes(32),
    );
    return NostrEvent(
      id: id,
      pubkey: publicKey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: _bytesToHex(signature),
    );
  }
}

String eventId({
  required String pubkey,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String content,
}) {
  final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
  return _bytesToHex(
    Uint8List.fromList(sha256.convert(utf8.encode(serialized)).bytes),
  );
}

BigInt _parseSecret(String secretHex) {
  final value = _bytesToBig(_hexToBytes(secretHex));
  if (value <= BigInt.zero || value >= _order) {
    throw const FormatException('私钥超出范围');
  }
  return value;
}

class _Point {
  const _Point(this.x, this.y);
  final BigInt x;
  final BigInt y;
}

BigInt _mod(BigInt value) {
  final result = value % _prime;
  return result.isNegative ? result + _prime : result;
}

_Point? _double(_Point? point) {
  if (point == null) return null;
  if (point.y == BigInt.zero) return null;
  final slope =
      _mod(BigInt.from(3) * point.x * point.x) *
      _modInverse(_mod(BigInt.two * point.y));
  final x = _mod(slope * slope - BigInt.two * point.x);
  final y = _mod(slope * (point.x - x) - point.y);
  return _Point(x, y);
}

_Point? _add(_Point? left, _Point? right) {
  if (left == null) return right;
  if (right == null) return left;
  if (left.x == right.x) {
    if (_mod(left.y + right.y) == BigInt.zero) return null;
    return _double(left);
  }
  final slope = _mod(right.y - left.y) * _modInverse(_mod(right.x - left.x));
  final x = _mod(slope * slope - left.x - right.x);
  final y = _mod(slope * (left.x - x) - left.y);
  return _Point(x, y);
}

_Point? _multiply(_Point? point, BigInt scalar) {
  _Point? result;
  _Point? current = point;
  var remaining = scalar;
  while (remaining > BigInt.zero) {
    if (remaining.isOdd) result = _add(result, current);
    current = _double(current);
    remaining = remaining >> 1;
  }
  return result;
}

_Point _multiplyGenerator(BigInt scalar) =>
    _multiply(_Point(_generatorX, _generatorY), scalar)!;

BigInt _modInverse(BigInt value) => value.modInverse(_prime);

Uint8List _sign({
  required Uint8List message,
  required BigInt secret,
  required _Point point,
  required Uint8List aux,
}) {
  if (message.length != 32) throw const FormatException('签名内容必须是 32 字节');
  if (aux.length != 32) throw const FormatException('辅助随机数必须是 32 字节');
  final normalized = point.y.isEven ? secret : _order - secret;
  final mask = _bytesToBig(_taggedHash('BIP0340/aux', aux));
  final tweaked = _bytes32(normalized ^ mask);
  final nonceHash = _taggedHash('BIP0340/nonce', [
    ...tweaked,
    ..._bigToBytes(point.x),
    ...message,
  ]);
  final nonce = _bytesToBig(nonceHash) % _order;
  if (nonce == BigInt.zero) throw StateError('随机数不可用，请重试');
  final noncePoint = _multiplyGenerator(nonce);
  final factor = noncePoint.y.isEven ? nonce : _order - nonce;
  final challenge =
      _bytesToBig(
        _taggedHash('BIP0340/challenge', [
          ..._bigToBytes(noncePoint.x),
          ..._bigToBytes(point.x),
          ...message,
        ]),
      ) %
      _order;
  return Uint8List.fromList([
    ..._bigToBytes(noncePoint.x),
    ..._bigToBytes((factor + challenge * normalized) % _order),
  ]);
}

Uint8List _taggedHash(String tag, List<int> message) {
  final tagHash = sha256.convert(utf8.encode(tag)).bytes;
  return Uint8List.fromList(
    sha256.convert([...tagHash, ...tagHash, ...message]).bytes,
  );
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  return bytes;
}

Uint8List _hexToBytes(String hex) {
  final text = hex.trim().toLowerCase();
  if (text.isEmpty || text.length.isOdd) {
    throw const FormatException('密钥格式无效');
  }
  final bytes = Uint8List(text.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    final value = int.tryParse(
      text.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
    if (value == null) throw const FormatException('密钥格式无效');
    bytes[index] = value;
  }
  return bytes;
}

String _bytesToHex(List<int> bytes) =>
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

BigInt _bytesToBig(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = value << 8 | BigInt.from(byte);
  }
  return value;
}

Uint8List _bigToBytes(BigInt value, [int length = 32]) {
  final bytes = Uint8List(length);
  var remaining = value;
  for (var index = length - 1; index >= 0; index--) {
    bytes[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}

Uint8List _bytes32(BigInt value) => _bigToBytes(value);

import 'dart:convert';
import 'dart:isolate';
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

  static const maxContentBytes = 512 * 1024;
  static const maxTags = 32;
  static const maxTagValues = 8;
  static const maxTagValueLength = 2048;
  static const futureToleranceSeconds = 5 * 60;

  // 这里只做廉价边界检查；签名必须在交给业务层之前另行验证。
  static NostrEvent? fromRelay(Object? raw, {int? nowSeconds}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final pubkey = raw['pubkey'];
    final sig = raw['sig'];
    final content = raw['content'];
    final createdAt = raw['created_at'];
    final kind = raw['kind'];
    final rawTags = raw['tags'];
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!_isHex(id, 64) || !_isHex(pubkey, 64) || !_isHex(sig, 128)) {
      return null;
    }
    if (createdAt is! int ||
        createdAt <= 0 ||
        createdAt > now + futureToleranceSeconds ||
        kind is! int ||
        kind < 0 ||
        kind > 65535 ||
        content is! String ||
        content.length > maxContentBytes ||
        utf8.encode(content).length > maxContentBytes ||
        rawTags is! List ||
        rawTags.length > maxTags) {
      return null;
    }
    final tags = <List<String>>[];
    for (final row in rawTags) {
      if (row is! List || row.isEmpty || row.length > maxTagValues) return null;
      final tag = <String>[];
      for (final value in row) {
        if (value is! String || value.length > maxTagValueLength) return null;
        tag.add(value);
      }
      tags.add(List<String>.unmodifiable(tag));
    }
    return NostrEvent(
      id: id as String,
      pubkey: pubkey as String,
      createdAt: createdAt,
      kind: kind,
      tags: List<List<String>>.unmodifiable(tags),
      content: content,
      sig: sig as String,
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

  static Future<NostrEvent> signAsync({
    required int kind,
    required int createdAt,
    required List<List<String>> tags,
    required String content,
    required String secretHex,
  }) => Isolate.run(
    () => sign(
      kind: kind,
      createdAt: createdAt,
      tags: tags,
      content: content,
      secretHex: secretHex,
    ),
  );

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

final _hexPattern = RegExp(r'^[0-9a-f]+$');

bool _isHex(Object? value, int length) =>
    value is String && value.length == length && _hexPattern.hasMatch(value);

Future<bool> verifyNostrEventAsync(NostrEvent event) =>
    Isolate.run(() => verifyNostrEvent(event));

bool verifyNostrEvent(NostrEvent event, {int? nowSeconds}) {
  if (NostrEvent.fromRelay(event.toJson(), nowSeconds: nowSeconds) == null) {
    return false;
  }
  if (event.id !=
      eventId(
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
      )) {
    return false;
  }
  return verifySchnorrSignature(
    publicKey: event.pubkey,
    message: event.id,
    signature: event.sig,
  );
}

/// BIP-340 的 x-only 公钥验证：lift_x 取偶数 y，R = sG - eP。
/// r、s 越界、无曲线点、无穷远点与奇数 y 都必须拒绝，不能取模后接受。
bool verifySchnorrSignature({
  required String publicKey,
  required String message,
  required String signature,
}) {
  if (!_isHex(publicKey, 64) ||
      !_isHex(message, 64) ||
      !_isHex(signature, 128)) {
    return false;
  }
  final x = BigInt.parse(publicKey, radix: 16);
  final r = BigInt.parse(signature.substring(0, 64), radix: 16);
  final s = BigInt.parse(signature.substring(64), radix: 16);
  if (x >= _prime || r >= _prime || s >= _order) return false;
  final squaredY = _mod(x * x * x + BigInt.from(7));
  var y = squaredY.modPow((_prime + BigInt.one) >> 2, _prime);
  if (_mod(y * y) != squaredY) return false;
  if (y.isOdd) y = _prime - y;
  final challenge =
      _bytesToBig(
        _taggedHash('BIP0340/challenge', [
          ..._bigToBytes(r),
          ..._bigToBytes(x),
          ..._hexToBytes(message),
        ]),
      ) %
      _order;
  final result = _add(
    _multiply(_Point(_generatorX, _generatorY), s),
    _multiply(_Point(x, y), (_order - challenge) % _order),
  );
  return result != null && result.y.isEven && result.x == r;
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

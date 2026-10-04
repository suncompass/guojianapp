import 'dart:convert';
import 'dart:typed_data';

import 'package:duanju_app/recommendation_store.dart';
import 'package:duanju_app/secret_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('duanju/device');
const _identityKey = 'recommend.v1.default.identity';
const _secret =
    'c0ffee1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
const _other =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// 可逆的替身：平台是否可用、能否解密都由这些开关控制。
class _FakePlatform {
  bool available = true;
  bool decryptable = true;

  Future<Object?> handle(MethodCall call) async {
    if (!available) throw MissingPluginException('未实现 ${call.method}');
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'protectSecret':
        return Uint8List.fromList(utf8.encode('sealed:${arguments['value']}'));
      case 'unprotectSecret':
        if (!decryptable) return null;
        final text = utf8.decode(arguments['blob'] as Uint8List);
        return text.startsWith('sealed:') ? text.substring(7) : null;
    }
    throw MissingPluginException('未实现 ${call.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late RecommendationStore store;
  late _FakePlatform platform;

  void bind() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, platform.handle);

  Future<void> restart() async {
    // 模拟重新启动：清掉内存缓存后只按落盘内容预载。
    SecretStore.reset();
    await SecretStore.initialize(preferences);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = RecommendationStore(preferences);
    platform = _FakePlatform();
    bind();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('平台不支持时退回明文，身份照常可用', () async {
    platform.available = false;
    await restart();
    await store.setIdentity('default', _secret);
    expect(store.identity('default'), _secret);
    expect(preferences.getString(_identityKey), _secret);
    expect(preferences.getString('$_identityKey.secret'), isNull);
  });

  test('已有的明文记录在平台不支持时保持不变', () async {
    platform.available = false;
    await preferences.setString(_identityKey, _secret);
    await restart();
    await store.upgradeIdentity('default');
    expect(store.identity('default'), _secret);
    expect(preferences.getString(_identityKey), _secret);
  });

  test('安全存储可用时写入密文，跨进程确认后才清除明文', () async {
    await preferences.setString(_identityKey, _secret);
    await restart();
    expect(store.identity('default'), _secret);

    // 第一次迁移：密文写入，明文保留，等下一次启动复核。
    await store.upgradeIdentity('default');
    expect(preferences.getString(_identityKey), _secret);
    expect(preferences.getString('$_identityKey.secret'), isNotNull);
    expect(store.identity('default'), _secret);

    // 下一次启动：密文仍能解出同一内容，此时才清除明文。
    await restart();
    expect(store.identity('default'), _secret);
    await store.upgradeIdentity('default');
    expect(preferences.getString(_identityKey), isNull);
    expect(store.identity('default'), _secret);
    expect(store.hasStoredIdentity('default'), isTrue);
  });

  test('新身份先写密文再等下一次启动清理明文', () async {
    await restart();
    await store.setIdentity('default', _secret);
    expect(preferences.getString(_identityKey), _secret);
    await restart();
    await store.upgradeIdentity('default');
    expect(preferences.getString(_identityKey), isNull);
    expect(store.identity('default'), _secret);
  });

  test('密文解不开时保留记录标记且不覆盖明文', () async {
    await preferences.setString(
      '$_identityKey.secret',
      base64Encode(utf8.encode('broken')),
    );
    await restart();
    expect(store.identity('default'), isNull);
    expect(store.hasStoredIdentity('default'), isTrue);

    // 反复迁移不得把已有记录当成新用户，也不得丢弃那个解不开的密文。
    await store.upgradeIdentity('default');
    expect(preferences.getString('$_identityKey.secret'), isNotNull);
    expect(store.hasStoredIdentity('default'), isTrue);
  });

  test('密文解不开但仍有明文时继续沿用明文', () async {
    await preferences.setString(_identityKey, _secret);
    await preferences.setString(
      '$_identityKey.secret',
      base64Encode(utf8.encode('broken')),
    );
    await restart();
    expect(store.identity('default'), _secret);
    await store.upgradeIdentity('default');
    expect(preferences.getString(_identityKey), _secret);
  });

  test('损坏的密文编码不会影响明文回退', () async {
    await preferences.setString(_identityKey, _secret);
    await preferences.setString('$_identityKey.secret', '不是 base64');
    await restart();
    expect(store.identity('default'), _secret);
  });

  test('更换身份会同时覆盖密文', () async {
    await restart();
    await store.setIdentity('default', _secret);
    await store.setIdentity('default', _other);
    await restart();
    expect(store.identity('default'), _other);
    await store.upgradeIdentity('default');
    expect(store.identity('default'), _other);
  });

  test('删除用户会一并清理密文记录', () async {
    await restart();
    await store.setIdentity('ghost', _secret);
    await store.pruneProfiles({'default'});
    expect(preferences.getString('recommend.v1.ghost.identity'), isNull);
    expect(preferences.getString('recommend.v1.ghost.identity.secret'), isNull);
  });

  test('预载是幂等的，重复调用不改变结果', () async {
    await preferences.setString(_identityKey, _secret);
    await SecretStore.initialize(preferences);
    await SecretStore.initialize(preferences);
    expect(SecretStore.ready, isTrue);
    expect(SecretStore.cached(_identityKey), _secret);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备安全存储：交给系统密钥保护记录，平台不支持或解不开时回退原有明文位置。
///
/// Android 用 Keystore 里的 AES-GCM 密钥，Windows 用 DPAPI；两端都只回传密文字节，
/// 存放位置仍由 SharedPreferences 决定，因此不需要额外的文件路径或读写权限。
/// 任何失败都必须退化为原有明文行为：加密不可用不能变成身份不可用。
class SecretStore {
  SecretStore._();

  static const _channel = MethodChannel('duanju/device');
  static const suffix = '.secret';
  static const _timeout = Duration(seconds: 5);

  static final Map<String, String> _cache = {};
  static Future<void>? _loading;
  static bool _ready = false;
  static bool _unsupported = false;

  /// 预载是否结束。结束前无法判断本机是否已有加密记录，调用方不得据此新建身份。
  static bool get ready => _ready;

  @visibleForTesting
  static void reset() {
    _cache.clear();
    _loading = null;
    _ready = false;
    _unsupported = false;
  }

  /// 启动时预载一次，之后读取走同步缓存。
  static Future<void> initialize(SharedPreferences preferences) {
    if (_ready) return Future<void>.value();
    return _loading ??= _load(preferences).whenComplete(() => _ready = true);
  }

  static Future<void> _load(SharedPreferences preferences) async {
    _cache.clear();
    for (final stored in preferences.getKeys().toList()) {
      if (!stored.endsWith(suffix)) continue;
      final name = stored.substring(0, stored.length - suffix.length);
      final value = await _unprotect(preferences.getString(stored));
      if (value != null) _cache[name] = value;
    }
  }

  /// 已解出的明文，仅在使用同一进程内有效。
  static String? cached(String key) => _cache[key];

  /// 交给平台加密并落盘；返回 true 只表示本次能解回同一内容。
  ///
  /// 这里不写缓存：跨进程可用性由下一次启动的预载确认，调用方应在此之前保留明文。
  static Future<bool> write(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    final blob = await _protect(value);
    if (blob == null || blob.isEmpty) return false;
    final encoded = base64Encode(blob);
    try {
      if (!await preferences.setString('$key$suffix', encoded)) return false;
    } on Object {
      return false;
    }
    return await _unprotect(encoded) == value;
  }

  static Future<void> remove(SharedPreferences preferences, String key) async {
    _cache.remove(key);
    await preferences.remove('$key$suffix');
  }

  static Future<Uint8List?> _protect(String value) async {
    if (_unsupported) return null;
    try {
      return await _channel
          .invokeMethod<Uint8List>('protectSecret', {'value': value})
          .timeout(_timeout);
    } on MissingPluginException {
      // 平台没有实现保护能力，不再重复请求；加密失败仍按临时故障处理。
      _unsupported = true;
      return null;
    } on Object {
      return null;
    }
  }

  static Future<String?> _unprotect(String? encoded) async {
    if (encoded == null || encoded.isEmpty) return null;
    if (_unsupported) return null;
    final Uint8List blob;
    try {
      blob = base64Decode(encoded);
    } on FormatException {
      return null;
    }
    try {
      final value = await _channel
          .invokeMethod<String>('unprotectSecret', {'blob': blob})
          .timeout(_timeout);
      return value == null || value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }
}

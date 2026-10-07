import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'core_bridge.dart';

/// 站源的出口亲和性不一致：一部分站源对机房与代理 IP 直接重置 TLS 握手，
/// 或者在 WAF 上拒绝，必须从本机网络出去；另一部分的媒体 CDN 恰好相反，
/// 只有走代理才通。应用无法知道用户代理软件的分流规则，所以不做站源表，
/// 改成失败驱动的换出口重试：先用当前出口尝试，失败且检测到系统 VPN 时
/// 临时把进程绑到物理网络再试一次，随后立刻恢复。
class NetworkExit {
  static const _channel = MethodChannel('duanju/device');

  static bool _borrowed = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _signals = <String>[
    'eof',
    'connection reset',
    'connection refused',
    'connection aborted',
    'broken pipe',
    'no route to host',
    'network is unreachable',
    'ssl_error',
    'handshake',
    'http 403',
    'http 407',
    'http 429',
    'http 502',
    'http 503',
    '连接超时',
    '无法连接',
    '连接被重置',
  ];

  /// 浏览器验证类拦截判定的是出口 IP，换到物理网络只会更差，因此不触发
  /// 换出口重试，交给用户换节点。
  static const _exitSignals = <String>['浏览器验证', 'just a moment'];

  static bool worthBypassing(Object error) {
    final text = (error is AppFailure ? error.message : error.toString())
        .toLowerCase();
    if (_exitSignals.any(text.contains)) return false;
    return _signals.any(text.contains);
  }

  static const _tlsSignals = <String>[
    'eof',
    'connection reset',
    'connection aborted',
    'broken pipe',
    'ssl_error',
    'handshake',
    '连接被重置',
  ];

  /// 底层网络错误用户看不懂，而且这批错误几乎都是出口被站源拒绝造成的。
  /// 直接说明原因和可执行的下一步，避免用户反复点重试。
  static String describe(String raw) {
    final lower = raw.toLowerCase();
    final String hint;
    if (lower.contains('http 403') || raw.contains('浏览器验证')) {
      hint = '站源要求浏览器验证，当前网络出口被判定为可疑';
    } else if (_tlsSignals.any(lower.contains)) {
      hint = '站源重置了连接，当前网络出口被拒绝';
    } else if (lower.contains('timeout') || raw.contains('超时')) {
      hint = '连接站源超时';
    } else {
      return raw;
    }
    return '$raw\n$hint。切换代理节点或换一条网络后重试，同一出口反复重试不会恢复。';
  }

  static Future<bool> active() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('vpnActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> borrow() async {
    if (!supported || _borrowed) return false;
    if (!await active()) return false;
    try {
      final bound =
          await _channel.invokeMethod<bool>('bindPhysicalNetwork', {
            'enabled': true,
          }) ??
          false;
      _borrowed = bound;
      return bound;
    } catch (_) {
      return false;
    }
  }

  static Future<void> release() async {
    if (!_borrowed) return;
    _borrowed = false;
    try {
      await _channel.invokeMethod<bool>('bindPhysicalNetwork', {
        'enabled': false,
      });
    } catch (_) {
      // 恢复失败时忽略：下一次借用前会重新绑定。
    }
  }
}

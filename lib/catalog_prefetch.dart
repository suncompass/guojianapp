import 'dart:async';

import 'package:flutter/foundation.dart';

/// 首页懒加载的提前量调度：滚动期间只做追加，把取下一页放到停止滚动之后，
/// 使用户到达底部时内容已经就位。
class CatalogPrefetchScheduler {
  CatalogPrefetchScheduler({
    this.bufferScreens = 2,
    this.idleDelay = const Duration(milliseconds: 320),
    this.maxRounds = 3,
  });

  final double bufferScreens;
  final Duration idleDelay;
  final int maxRounds;

  VoidCallback? onIdle;

  Timer? _timer;
  bool _idle = true;
  bool _paused = false;
  bool _armed = false;
  bool _disposed = false;
  int _rounds = 0;
  double _extentAfter = 0;
  double _viewport = 0;

  @visibleForTesting
  bool get idle => _idle;

  @visibleForTesting
  bool get armed => _armed;

  @visibleForTesting
  bool get paused => _paused;

  @visibleForTesting
  int get rounds => _rounds;

  bool get wantsMore {
    if (_viewport <= 0) return false;
    return _extentAfter < _viewport * bufferScreens;
  }

  void scrolled({required double extentAfter, required double viewport}) {
    if (_disposed) return;
    _paused = false;
    _extentAfter = extentAfter;
    _viewport = viewport;
    _armed = true;
    _idle = false;
    _rounds = 0;
    _arm();
  }

  void settled({required double extentAfter, required double viewport}) {
    if (_disposed || _paused) return;
    _extentAfter = extentAfter;
    _viewport = viewport;
    _armed = true;
    if (_idle) {
      _notify();
      return;
    }
    _arm();
  }

  /// 重新进入首页时解除暂停；不主动取页，等下一次布局结果再判断。
  void resume() {
    if (_disposed) return;
    _paused = false;
  }

  void hold() {
    if (_disposed) return;
    _paused = true;
    _idle = true;
    _rounds = 0;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    onIdle = null;
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(idleDelay, _expire);
  }

  void _expire() {
    _timer = null;
    _idle = true;
    if (!_armed) return;
    _notify();
  }

  void _notify() {
    if (_disposed || _paused) return;
    if (!_armed || _rounds >= maxRounds || !wantsMore) return;
    _rounds++;
    onIdle?.call();
  }
}

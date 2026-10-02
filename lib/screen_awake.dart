import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenAwake {
  bool _enabled = false;

  void enable() {
    if (_enabled) return;
    _enabled = true;
    _count++;
    _update();
  }

  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _count--;
    _update();
  }

  Future<void> _apply(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (error) {
      debugPrint('[ScreenAwake] $error');
    }
  }

  void _update() {
    unawaited(_apply(_count > 0));
  }

  static int _count = 0;
}

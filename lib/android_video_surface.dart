import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

const _viewType = 'duanju/video_surface';

bool get androidSurfaceViewSupported => !kIsWeb && Platform.isAndroid;

class VideoSurfaceHost extends StatefulWidget {
  const VideoSurfaceHost({super.key, required this.player, this.onUnavailable});

  final Player player;
  final VoidCallback? onUnavailable;

  @override
  State<VideoSurfaceHost> createState() => _VideoSurfaceHostState();
}

class _VideoSurfaceHostState extends State<VideoSurfaceHost> {
  static const _outputProperties = <String, String>{
    'vo': 'null',
    'hwdec': 'auto-safe',
    'vid': 'auto',
    'opengl-es': 'yes',
    'force-window': 'yes',
    'gpu-context': 'android',
    'sub-use-margins': 'no',
    'sub-font-provider': 'none',
    'sub-scale-with-window': 'yes',
    'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
  };

  AndroidViewController? _viewController;
  MethodChannel? _channel;
  Future<void> _operations = Future<void>.value();
  int? _wid;
  int _width = 0;
  int _height = 0;
  bool _attached = false;
  bool _failed = false;
  bool _disposed = false;

  NativePlayer get _native {
    final platform = widget.player.platform;
    if (platform is! NativePlayer) {
      throw UnsupportedError(
        '[VideoSurfaceHost] requires NativePlayer with video support.',
      );
    }
    return platform;
  }

  @override
  void initState() {
    super.initState();
    _enqueue(_configureOutput);
  }

  @override
  void dispose() {
    _disposed = true;
    _enqueue(_releaseOutput);
    super.dispose();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operations.then((_) => action());
    _operations = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _setProperties(Map<String, String> properties) async {
    final native = _native;
    await native.waitForPlayerInitialization;
    for (final entry in properties.entries) {
      await native.setProperty(
        entry.key,
        entry.value,
        waitForInitialization: false,
      );
    }
  }

  Future<void> _configureOutput() => _setProperties(_outputProperties);

  Future<void> _releaseOutput() async {
    if (_wid != null) {
      try {
        await _setProperties(const <String, String>{'vo': 'null'});
      } catch (_) {}
      _wid = null;
    }
    _channel?.setMethodCallHandler(null);
    _channel = null;
    final controller = _viewController;
    _viewController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  Future<void> _fail(Object error) async {
    if (_disposed || _failed) return;
    _failed = true;
    debugPrint('[VideoSurfaceHost] $error');
    await _enqueue(_releaseOutput);
    if (_disposed) return;
    widget.onUnavailable?.call();
  }

  Future<void> _detachSurface() async {
    _wid = null;
    _attached = false;
    try {
      await _setProperties(const <String, String>{'vo': 'null'});
    } catch (_) {}
  }

  Future<void> _attachSurface() async {
    final wid = _wid;
    if (_disposed || _failed || wid == null) return;
    if (_width <= 0 || _height <= 0) return;
    try {
      await _setProperties(<String, String>{
        'android-surface-size': '${_width}x$_height',
        'wid': '$wid',
        'vo': 'gpu',
      });
      if (_disposed || _failed) return;
      if (!_attached) {
        _attached = true;
        await widget.player.seek(widget.player.state.position);
      }
    } catch (error) {
      await _fail(error);
    }
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (_disposed || _failed) return;
    switch (call.method) {
      case 'surfaceCreated':
        final arguments = call.arguments as Map<Object?, Object?>;
        final wid = arguments['wid'];
        if (wid is! int || wid == 0) {
          await _fail('native surface reference unavailable');
          return;
        }
        _wid = wid;
        _width = (arguments['width'] as num?)?.toInt() ?? 0;
        _height = (arguments['height'] as num?)?.toInt() ?? 0;
        await _enqueue(_attachSurface);
      case 'surfaceChanged':
        final arguments = call.arguments as Map<Object?, Object?>;
        final width = (arguments['width'] as num?)?.toInt() ?? 0;
        final height = (arguments['height'] as num?)?.toInt() ?? 0;
        if (width <= 0 || height <= 0) return;
        if (width == _width && height == _height) return;
        _width = width;
        _height = height;
        if (_wid == null) return;
        await _enqueue(_attachSurface);
      case 'surfaceDestroyed':
        await _enqueue(_detachSurface);
      case 'surfaceUnavailable':
        await _fail('native surface reference unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!androidSurfaceViewSupported || _failed) {
      return const SizedBox.expand();
    }
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        );
      },
      onCreatePlatformView: (params) {
        final viewController = PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: Directionality.of(context),
          creationParamsCodec: const StandardMessageCodec(),
        );
        _viewController = viewController;
        _channel = MethodChannel('$_viewType/${params.id}')
          ..setMethodCallHandler(_onMethodCall);
        viewController
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
        return viewController;
      },
    );
  }
}

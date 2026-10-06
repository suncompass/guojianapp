import 'package:flutter/widgets.dart';

/// 只缩放合成层，不把面板动画的逐帧尺寸传给原生视频 Surface。
/// outputSize 按视频宽高比计算，避免先加黑边再缩放导致画面过小。
class StableVideoViewport extends StatelessWidget {
  const StableVideoViewport({
    super.key,
    required this.outputSize,
    required this.child,
  });

  final Size outputSize;
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    child: SizedBox.fromSize(
      size: outputSize,
      child: RepaintBoundary(child: child),
    ),
  );
}

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
  Widget build(BuildContext context) => ClipRect(
    child: CustomPaint(
      // 黑边必须画在原生视频上方，不能只依赖其下方的页面背景。
      foregroundPainter: _VideoLetterboxPainter(outputSize),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: outputSize,
          child: RepaintBoundary(child: child),
        ),
      ),
    ),
  );
}

class _VideoLetterboxPainter extends CustomPainter {
  const _VideoLetterboxPainter(this.outputSize);

  final Size outputSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || outputSize.isEmpty) return;
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final fitted = applyBoxFit(BoxFit.contain, outputSize, size);
    final picture = Alignment.center.inscribe(fitted.destination, bounds);
    final matte = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addRect(picture);
    canvas.drawPath(
      matte,
      Paint()
        ..color = const Color(0xFF000000)
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoLetterboxPainter oldDelegate) =>
      outputSize != oldDelegate.outputSize;
}

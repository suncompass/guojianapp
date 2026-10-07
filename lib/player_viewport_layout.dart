import 'package:flutter/material.dart';

/// 全屏只收展附属面板，视频始终留在同一个 Flex 槽位，不移树或交叉淡入。
class PlayerViewportLayout extends StatelessWidget {
  const PlayerViewportLayout({
    super.key,
    required this.fullscreen,
    required this.axis,
    required this.video,
    required this.panel,
    this.duration = const Duration(milliseconds: 220),
  });

  final bool fullscreen;
  final Axis axis;
  final Widget video;
  final Widget panel;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: fullscreen ? 0 : 1, end: fullscreen ? 0 : 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration,
    curve: Curves.easeInOutCubic,
    // 不在动画帧里构建视频或选集列表，只重新分配可见区域。
    child: IgnorePointer(
      ignoring: fullscreen,
      child: ExcludeFocus(
        excluding: fullscreen,
        // 全屏请求生效的第一帧就停止绘制面板；尺寸仍由外层动画收起，
        // 避免旋转时闪出选集，同时不拆卸视频或丢失面板滚动状态。
        child: Opacity(opacity: fullscreen ? 0 : 1, child: panel),
      ),
    ),
    builder: (context, fraction, child) => Flex(
      direction: axis,
      children: [
        Expanded(child: video),
        ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            widthFactor: axis == Axis.horizontal ? fraction : 1,
            heightFactor: axis == Axis.vertical ? fraction : 1,
            child: Visibility(
              visible: fraction > 0,
              maintainState: true,
              child: child!,
            ),
          ),
        ),
      ],
    ),
  );
}

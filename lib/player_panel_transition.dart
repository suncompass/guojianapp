import 'package:flutter/material.dart';

/// 固定内部约束，只改变裁剪高度，避免动画逐帧重建整块面板。
class PlayerPanelTransition extends StatefulWidget {
  const PlayerPanelTransition({
    super.key,
    required this.collapsed,
    required this.height,
    required this.headerHeight,
    required this.header,
    required this.child,
  });

  final bool collapsed;
  final double height;
  final double headerHeight;
  final Widget header;
  final Widget child;

  @override
  State<PlayerPanelTransition> createState() => _PlayerPanelTransitionState();
}

class _PlayerPanelTransitionState extends State<PlayerPanelTransition>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    value: widget.collapsed ? 0 : 1,
  )..addListener(_updateVisibility);
  late bool _contentVisible = !widget.collapsed;

  void _updateVisibility() {
    final visible = !widget.collapsed || _animation.value > 0;
    // 只在端点切换内容可见性，不在每一帧重建 Visibility 和内容布局。
    if (visible != _contentVisible) {
      setState(() => _contentVisible = visible);
    }
  }

  void _animate() {
    final target = widget.collapsed ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = target;
    } else {
      _animation.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(PlayerPanelTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) {
      if (!widget.collapsed) _contentVisible = true;
      _animate();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height < widget.headerHeight
        ? widget.headerHeight
        : widget.height;
    return AnimatedBuilder(
      animation: _animation,
      // 头部、Material 和内容保持尺寸与绘制层稳定；收起后保留滚动状态。
      child: SizedBox(
        height: height,
        child: RepaintBoundary(
          child: Material(
            key: const ValueKey('player-panel-background'),
            color: Colors.black,
            child: Column(
              children: [
                SizedBox(height: widget.headerHeight, child: widget.header),
                Expanded(
                  child: Visibility(
                    visible: _contentVisible,
                    maintainState: true,
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor:
              (widget.headerHeight +
                  (height - widget.headerHeight) * _animation.value) /
              height,
          child: child,
        ),
      ),
    );
  }
}

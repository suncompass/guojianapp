import 'dart:async';

import 'package:flutter/material.dart';

/// 自动连播的非阻塞提示：快切不闪，慢切轻提示，不驱动视频层透明度。
class PlayerEpisodeTransition extends StatefulWidget {
  const PlayerEpisodeTransition({super.key, required this.episodeNumber});

  final int? episodeNumber;

  @override
  State<PlayerEpisodeTransition> createState() =>
      _PlayerEpisodeTransitionState();
}

class _PlayerEpisodeTransitionState extends State<PlayerEpisodeTransition> {
  Timer? _delay;
  int? _number;
  bool _visible = false;

  void _schedule() {
    _delay?.cancel();
    _visible = false;
    final number = widget.episodeNumber;
    if (number == null) return;
    // 延时仅控制提示，不延迟地址解析、播放器打开或下一集起播。
    _delay = Timer(const Duration(milliseconds: 240), () {
      if (!mounted || widget.episodeNumber != number) return;
      setState(() {
        _number = number;
        _visible = true;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(PlayerEpisodeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeNumber != widget.episodeNumber) _schedule();
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      excluding: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        onEnd: () {
          // 零动画时 onEnd 可能在子组件更新期间同步触发，延后清理父状态。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                !_visible &&
                widget.episodeNumber == null &&
                _number != null) {
              setState(() => _number = null);
            }
          });
        },
        child: _number == null
            ? const SizedBox.expand()
            : RepaintBoundary(child: _hint()),
      ),
    ),
  );

  Widget _hint() => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
            stops: [0, .65],
          ),
        ),
      ),
      Align(
        alignment: const Alignment(0, .6),
        child: Semantics(
          liveRegion: true,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xB3000000),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '即将播放 · 第 $_number 集',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

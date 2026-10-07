import 'package:duanju_app/player_viewport_layout.dart';
import 'package:duanju_app/stable_video_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PanelPainter extends CustomPainter {
  _PanelPainter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant _PanelPainter oldDelegate) => false;
}

void main() {
  for (final axis in Axis.values) {
    testWidgets('fullscreen keeps $axis media mounted through transitions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const surfaceKey = ValueKey('native-surface');
      const panelKey = ValueKey('episode-panel');
      final layouts = <Size>[];
      final video = StableVideoViewport(
        outputSize: const Size(390, 690),
        child: LayoutBuilder(
          builder: (context, constraints) {
            layouts.add(constraints.biggest);
            return const SizedBox.expand(key: surfaceKey);
          },
        ),
      );
      var panelPaints = 0;
      final panel = SizedBox(
        key: panelKey,
        width: axis == Axis.horizontal ? 160 : null,
        height: axis == Axis.vertical ? 200 : null,
        child: CustomPaint(
          painter: _PanelPainter(() => panelPaints++),
          child: const SizedBox.expand(),
        ),
      );
      Future<void> render(bool fullscreen, {bool disableAnimations = false}) {
        return tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: PlayerViewportLayout(
                fullscreen: fullscreen,
                axis: axis,
                video: video,
                panel: panel,
              ),
            ),
          ),
        );
      }

      double extent() {
        final size = tester.getSize(find.byType(StableVideoViewport));
        return axis == Axis.vertical ? size.height : size.width;
      }

      await render(false);
      final surfaceElement = tester.element(find.byKey(surfaceKey));
      final panelElement = tester.element(find.byKey(panelKey));
      final initialExtent = extent();
      final paintsBeforeFullscreen = panelPaints;
      expect(paintsBeforeFullscreen, greaterThan(0));
      await render(true);
      expect(extent(), initialExtent, reason: '切换请求不能让布局瞬间跳到终点');
      expect(panelPaints, paintsBeforeFullscreen, reason: '全屏首帧不能绘制选集');
      await tester.pump(const Duration(milliseconds: 100));
      expect(extent(), greaterThan(initialExtent));
      expect(panelPaints, paintsBeforeFullscreen, reason: '动画中间帧不能漏出选集');
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(panelPaints, paintsBeforeFullscreen, reason: '旋转重布局也不能绘制选集');
      expect(tester.element(find.byKey(surfaceKey)), same(surfaceElement));
      tester.view.physicalSize = const Size(390, 844);
      // 收起尚未完成就反向展开，继续沿用原视频与面板状态。
      await render(false);
      await tester.pump(const Duration(milliseconds: 240));
      expect(extent(), initialExtent);
      expect(panelPaints, greaterThan(paintsBeforeFullscreen));
      expect(tester.element(find.byKey(panelKey)), same(panelElement));
      await render(true);
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byKey(panelKey), findsNothing);
      expect(extent(), axis == Axis.vertical ? 844 : 390);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(extent(), axis == Axis.vertical ? 390 : 844);
      expect(tester.element(find.byKey(surfaceKey)), same(surfaceElement));
      // 旋转与全屏动画都只改变外层合成尺寸，不触发原生输出重布局。
      expect(layouts, [const Size(390, 690)]);
      await render(false, disableAnimations: true);
      await tester.pump();
      expect(find.byKey(panelKey), findsOneWidget);
      expect(tester.element(find.byKey(panelKey)), same(panelElement));
      expect(tester.element(find.byKey(surfaceKey)), same(surfaceElement));
      expect(tester.takeException(), isNull);
    });
  }
}

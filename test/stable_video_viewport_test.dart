import 'dart:ui' as ui;

import 'package:duanju_app/stable_video_viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final ratio in [9 / 16, 16 / 9]) {
    testWidgets('panel resizing keeps $ratio video output constraints stable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final outputSize = Size(390, 390 / ratio);
      final layouts = <BoxConstraints>[];
      const surfaceKey = ValueKey('native-surface');
      final viewport = StableVideoViewport(
        outputSize: outputSize,
        child: LayoutBuilder(
          builder: (context, constraints) {
            layouts.add(constraints);
            return const SizedBox.expand(key: surfaceKey);
          },
        ),
      );
      for (final height in [460.0, 520.0, 600.0, 780.0, 600.0, 460.0]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 390, height: height, child: viewport),
            ),
          ),
        );
        final surface = tester.renderObject<RenderBox>(find.byKey(surfaceKey));
        expect(surface.size, outputSize);
        final start = surface.localToGlobal(Offset.zero);
        final end = surface.localToGlobal(
          Offset(outputSize.width, outputSize.height),
        );
        final painted = end - start;
        expect(painted.dx / painted.dy, closeTo(ratio, .001));
        expect(painted.dx, lessThanOrEqualTo(390.01));
        expect(painted.dy, lessThanOrEqualTo(height + .01));
      }
      expect(layouts, hasLength(1));
      expect(layouts.single.biggest, outputSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('letterbox covers stale pixels for $ratio video on rotation', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const viewportKey = ValueKey('painted-viewport');
      const surfaceKey = ValueKey('native-surface');
      final outputSize = Size(320, 320 / ratio);
      final viewport = StableVideoViewport(
        outputSize: outputSize,
        child: const ColoredBox(key: surfaceKey, color: Color(0xFF00FF00)),
      );
      Element? surfaceElement;
      for (final size in [const Size(390, 844), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: viewportKey,
              child: ColoredBox(
                color: const Color(0xFFFF0000),
                child: viewport,
              ),
            ),
          ),
        );
        surfaceElement ??= tester.element(find.byKey(surfaceKey));
        expect(tester.element(find.byKey(surfaceKey)), same(surfaceElement));
        expect(tester.getSize(find.byKey(surfaceKey)), outputSize);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(viewportKey),
        );
        final fitted = applyBoxFit(BoxFit.contain, outputSize, size);
        final picture = Alignment.center.inscribe(
          fitted.destination,
          Rect.fromLTWH(0, 0, size.width, size.height),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(data, isNotNull);
            final pixels = data!.buffer.asUint8List();
            for (final y in [0, image.height ~/ 2, image.height - 1]) {
              for (final x in [0, image.width ~/ 2, image.width - 1]) {
                final offset = (y * image.width + x) * 4;
                final inPicture = picture.contains(Offset(x + .5, y + .5));
                expect(
                  pixels.sublist(offset, offset + 4),
                  inPicture ? [0, 255, 0, 255] : [0, 0, 0, 255],
                  reason: '旋转后黑边不能透出旧页面，视频区域不能被遮住',
                );
              }
            }
          } finally {
            image.dispose();
          }
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
}

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
        final surface = tester.renderObject<RenderBox>(
          find.byKey(surfaceKey),
        );
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
  }
}

import 'package:duanju_app/player_panel_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeBox(onLayout);
}

class _ProbeBox extends RenderProxyBox {
  _ProbeBox(this.onLayout);
  final VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

void main() {
  testWidgets('panel animation reuses content builds and layout', (tester) async {
    var collapsed = false;
    var builds = 0;
    var layouts = 0;
    late StateSetter update;
    final content = _LayoutProbe(
      onLayout: () => layouts++,
      child: Builder(
        builder: (context) {
          builds++;
          return const SizedBox.expand(key: ValueKey('content'));
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  const Expanded(child: SizedBox()),
                  PlayerPanelTransition(
                    collapsed: collapsed,
                    height: 300,
                    headerHeight: 48,
                    header: const SizedBox(),
                    child: content,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    final element = tester.element(find.byKey(const ValueKey('content')));
    update(() => collapsed = true);
    await tester.pump();
    final initialBuilds = builds;
    final initialLayouts = layouts;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, initialBuilds);
    expect(layouts, initialLayouts);
    expect(tester.element(find.byKey(const ValueKey('content'))), same(element));
    // 动画中途反向仍保留同一棵内容树。
    update(() => collapsed = false);
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('content'))), same(element));
    update(() => collapsed = true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content')), findsNothing);
    expect(tester.getSize(find.byType(PlayerPanelTransition)).height, 48);
    update(() => collapsed = false);
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('content'))), same(element));
    expect(tester.getSize(find.byType(PlayerPanelTransition)).height, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled animations and initial collapse keep header reachable', (
    tester,
  ) async {
    var collapsed = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  PlayerPanelTransition(
                    collapsed: collapsed,
                    height: 300,
                    headerHeight: 48,
                    header: const Text('header'),
                    child: const Text('body'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('header'), findsOneWidget);
    expect(find.text('body'), findsNothing);
    update(() => collapsed = false);
    await tester.pump();
    expect(tester.getSize(find.byType(PlayerPanelTransition)).height, 300);
    expect(find.text('body'), findsOneWidget);
    update(() => collapsed = true);
    await tester.pump();
    expect(tester.getSize(find.byType(PlayerPanelTransition)).height, 48);
    expect(tester.takeException(), isNull);
  });
}

import 'package:duanju_app/player_episode_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(int? episode, {bool disabled = false, VoidCallback? onTap}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disabled),
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: TextButton(
                  key: const ValueKey('underlay-action'),
                  onPressed: onTap ?? () {},
                  child: const Text('controls'),
                ),
              ),
              PlayerEpisodeTransition(episodeNumber: episode),
            ],
          ),
        ),
      ),
    );

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(PlayerEpisodeTransition),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

void main() {
  testWidgets('fast transitions cancel the hint without a flash', (
    tester,
  ) async {
    await tester.pumpWidget(_host(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('即将播放 · 第 2 集'), findsNothing);
    await tester.pumpWidget(_host(null));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('即将播放 · 第 2 集'), findsNothing);
    expect(_opacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow transitions fade both ways without blocking controls', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(2, onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('即将播放 · 第 2 集'), findsOneWidget);
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.tap(find.byKey(const ValueKey('underlay-action')));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 180));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_host(null));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(find.text('即将播放 · 第 2 集'), findsNothing);
    expect(_opacity(tester), 0);
  });

  testWidgets('rapid replacement only shows the latest episode', (
    tester,
  ) async {
    await tester.pumpWidget(_host(2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(3));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('即将播放 · 第 2 集'), findsNothing);
    expect(find.text('即将播放 · 第 3 集'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables fades and pending timers are disposed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(2, disabled: true));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_host(null, disabled: true));
    await tester.pump();
    expect(_opacity(tester), 0);
    await tester.pumpWidget(_host(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

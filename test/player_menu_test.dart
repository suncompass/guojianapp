import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_menu.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openMenu(
  WidgetTester tester, {
  required Size size,
  PlayerMenuSection section = PlayerMenuSection.episodes,
  FakeViewPadding systemPadding = const FakeViewPadding(),
  ValueChanged<int?>? onClosed,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = systemPadding;
  tester.view.padding = const FakeViewPadding();
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  final episodes = List.generate(120, (index) => Episode({}, index + 1));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final selected = await showDialog<int>(
                context: context,
                builder: (context) => PlayerMenu(
                  section: section,
                  episodes: episodes,
                  currentIndex: 0,
                  preferences: const PlaybackPreferences(),
                  qualities: const [1080, 720],
                  actualQuality: 1080,
                  local: false,
                  favorite: false,
                  mobile: true,
                  onEpisode: (index) => Navigator.pop(context, index),
                  onPreferences: (_) async {},
                  onFavorite: () async {},
                ),
              );
              onClosed?.call(selected);
            },
            child: const Text('打开菜单'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开菜单'));
  await tester.pumpAndSettle();
}

void main() {
  for (final layout in [
    (size: const Size(320, 280), width: 296.0, columns: 3),
    (size: const Size(568, 320), width: 320.0, columns: 3),
    (size: const Size(844, 390), width: 379.8, columns: 4),
    (size: const Size(1024, 768), width: 460.8, columns: 5),
    (size: const Size(1920, 1080), width: 520.0, columns: 5),
  ]) {
    testWidgets('landscape episode drawer adapts to ${layout.size}', (
      tester,
    ) async {
      await _openMenu(tester, size: layout.size);
      final drawer = tester.getRect(
        find.byKey(const ValueKey('player-menu-drawer')),
      );
      expect(drawer.width, closeTo(layout.width, .1));
      expect(drawer.right, closeTo(layout.size.width - 12, .1));
      expect(drawer.left, greaterThanOrEqualTo(12));
      expect(
        tester.widget<RemoteGrid>(find.byType(RemoteGrid)).columns,
        layout.columns,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wider drawer respects system bars and keeps selection working', (
    tester,
  ) async {
    final selections = <int?>[];
    await _openMenu(
      tester,
      size: const Size(844, 390),
      systemPadding: const FakeViewPadding(right: 48, bottom: 24),
      onClosed: selections.add,
    );
    final drawer = tester.getRect(
      find.byKey(const ValueKey('player-menu-drawer')),
    );
    expect(drawer.width, closeTo(379.8, .1));
    expect(drawer.right, lessThanOrEqualTo(844 - 48 - 12));
    expect(drawer.bottom, lessThanOrEqualTo(390 - 24 - 12));
    expect(
      tester
          .widget<RemoteEpisodeButton>(
            find.byKey(const ValueKey('menu-episode-1')),
          )
          .current,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('menu-episode-2')));
    await tester.pumpAndSettle();
    expect(selections, [1]);
    expect(find.byKey(const ValueKey('player-menu')), findsNothing);

    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭菜单'));
    await tester.pumpAndSettle();
    expect(selections, [1, null]);
    expect(find.byKey(const ValueKey('player-menu')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait episode menu retains its bottom sheet layout', (
    tester,
  ) async {
    await _openMenu(tester, size: const Size(390, 844));
    final drawer = tester.getRect(
      find.byKey(const ValueKey('player-menu-drawer')),
    );
    expect(drawer.width, closeTo(366, .1));
    expect(drawer.height, closeTo(844 * .72, .1));
    expect(drawer.bottom, closeTo(844 - 12, .1));
    expect(tester.takeException(), isNull);
  });

  for (final section in [
    PlayerMenuSection.speed,
    PlayerMenuSection.quality,
    PlayerMenuSection.settings,
  ]) {
    testWidgets('landscape $section keeps its original width', (tester) async {
      await _openMenu(tester, size: const Size(844, 390), section: section);
      final drawer = tester.getRect(
        find.byKey(const ValueKey('player-menu-drawer')),
      );
      expect(drawer.width, closeTo(440, .1));
      expect(tester.takeException(), isNull);
    });
  }
}

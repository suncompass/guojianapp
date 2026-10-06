import 'dart:collection';

import 'package:duanju_app/episode_browser.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingEpisodes extends ListBase<Episode> {
  _CountingEpisodes(int count)
    : _items = List.generate(count, (index) => Episode({}, index + 1));
  final List<Episode> _items;
  int reads = 0;

  @override
  int get length => _items.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  Episode operator [](int index) {
    reads++;
    return _items[index];
  }

  @override
  void operator []=(int index, Episode value) =>
      throw UnsupportedError('read only');
}

Widget _host(
  List<Episode> episodes,
  int current, {
  ValueChanged<int>? onSelected,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 390,
        height: 280,
        child: EpisodeBrowser(
          episodes: episodes,
          currentNumber: current,
          compact: true,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
  ),
);

void _expectVisible(WidgetTester tester, int number) {
  final item = find.byKey(ValueKey('episode-$number'));
  expect(item.hitTestable(), findsOneWidget);
  final grid = tester.getRect(
    find.byKey(const ValueKey('compact-episode-grid')),
  );
  final rect = tester.getRect(item);
  expect(rect.top, greaterThanOrEqualTo(grid.top));
  expect(rect.bottom, lessThanOrEqualTo(grid.bottom));
}

void main() {
  testWidgets('large compact lists stay lazy and do not rescan on rebuild', (
    tester,
  ) async {
    final episodes = _CountingEpisodes(20000);
    await tester.pumpWidget(_host(episodes, 15001));
    await tester.pumpAndSettle();
    _expectVisible(tester, 15001);
    expect(find.text('15001-15050').hitTestable(), findsOneWidget);
    expect(find.byType(RemoteEpisodeButton).evaluate().length, lessThan(100));
    expect(find.byType(RemoteGrid), findsNothing);
    final grid = find.byKey(const ValueKey('compact-episode-grid'));
    final element = tester.element(grid);
    final controller = tester.widget<GridView>(grid).controller!;
    final offset = controller.offset;
    episodes.reads = 0;
    for (var rebuild = 0; rebuild < 3; rebuild++) {
      await tester.pumpWidget(_host(episodes, 15001));
      await tester.pumpAndSettle();
    }
    expect(episodes.reads, lessThan(500));
    expect(tester.element(grid), same(element));
    expect(controller.offset, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late range jumps are accurate and preserve the grid element', (
    tester,
  ) async {
    final episodes = _CountingEpisodes(10000);
    await tester.pumpWidget(_host(episodes, 9001));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('compact-episode-grid'));
    final element = tester.element(grid);
    await tester.tap(find.text('8951-9000'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 8951);
    expect(tester.element(grid), same(element));
    final controller = tester.widget<GridView>(grid).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(RemoteEpisodeButton).evaluate().length, lessThan(100));
    await tester.tap(find.text('8951-9000'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 8951);
    await tester.tap(find.byTooltip('定位当前'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 9001);
    expect(tester.takeException(), isNull);
  });

  testWidgets('data replacement and sparse episode numbers refresh the index', (
    tester,
  ) async {
    var selected = -1;
    final episodes = _CountingEpisodes(2000);
    await tester.pumpWidget(_host(episodes, 1800));
    await tester.pumpAndSettle();
    final replacement = [
      for (final number in [12, 42, 81]) Episode({}, number),
    ];
    await tester.pumpWidget(
      _host(replacement, 42, onSelected: (index) => selected = index),
    );
    await tester.pumpAndSettle();
    _expectVisible(tester, 42);
    final item = find.byKey(const ValueKey('episode-42'));
    expect(tester.widget<RemoteEpisodeButton>(item).current, isTrue);
    await tester.tap(item);
    expect(selected, 1);
    await tester.pumpWidget(_host(const [], 0));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteEpisodeButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

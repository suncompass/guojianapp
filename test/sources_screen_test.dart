import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/sources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<LocalStore> mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  addTearDown(store.dispose);
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SourcesScreen(repository: FixtureRepository(), store: store),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return store;
}

void main() {
  testWidgets('every 黄果 entrance forms its own card like other sources', (
    tester,
  ) async {
    final store = await mount(tester);
    for (final id in ['huangguo-video', 'huangguoai', 'cloudfront']) {
      final card = find.byKey(ValueKey('source-$id'));
      await tester.scrollUntilVisible(
        card,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(card, findsOneWidget, reason: '$id 应与其他站源一样独立成卡片');
    }
    expect(find.text('黄果'), findsNothing, reason: '不再使用黄果折叠分组');
    expect(find.byType(ExpansionTile), findsNothing);
    expect(store.sources.length, SourceSite.values.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a 黄果 card and its actions keeps the app alive', (
    tester,
  ) async {
    await mount(tester);
    final card = find.byKey(const ValueKey('source-huangguo-video'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(card);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    final update = find.byKey(const ValueKey('update-huangguo-video'));
    expect(update, findsOneWidget);
    await tester.tap(update);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:duanju_app/feeds_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/nostr_crypto.dart';
import 'package:duanju_app/nostr_relay.dart';
import 'package:duanju_app/recommendation_models.dart';
import 'package:duanju_app/recommendation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class _FakeRelay extends NostrRelayPool {
  _FakeRelay(
    super.relays, {
    required super.onEvent,
    super.onStatus,
    super.onNotice,
  });

  @override
  void start({
    required int kind,
    required String dTag,
    String subscription = 'zhenguo-feed',
  }) {
    onStatus?.call();
  }

  @override
  Future<int> publish(NostrEvent event) async => 1;

  @override
  int get connected => 2;

  @override
  int get total => 5;

  @override
  Future<void> dispose() async {}
}

void main() {
  late SharedPreferences preferences;
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = LocalStore(preferences);
  });

  tearDown(() {
    RecommendationService.current?.dispose();
    RecommendationService.current = null;
    store.dispose();
  });

  testWidgets('底部导航新增动态入口并显示空榜提示', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RecommendationService.current = RecommendationService(
      preferences,
      relayFactory: (relays, onEvent, onStatus, onNotice) => _FakeRelay(
        relays,
        onEvent: onEvent,
        onStatus: onStatus,
        onNotice: onNotice,
      ),
    );
    await tester.pumpWidget(
      DuanjuApp(repository: FixtureRepository(), store: store),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bottom-nav-1')), findsOneWidget);
    expect(find.text('在看'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    expect(find.byType(FeedsScreen), findsOneWidget);
    expect(find.text('还没有人推荐短剧'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-source-filters')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-category-filters')), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
    expect(find.byKey(const ValueKey('feed-refresh')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('其他用户的推荐进入榜单后显示条数与站源', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late _FakeRelay relay;
    RecommendationService.current = RecommendationService(
      preferences,
      relayFactory: (relays, onEvent, onStatus, onNotice) => relay = _FakeRelay(
        relays,
        onEvent: onEvent,
        onStatus: onStatus,
        onNotice: onNotice,
      ),
    );
    await tester.pumpWidget(
      DuanjuApp(repository: FixtureRepository(), store: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();

    final other = NostrIdentity.generate();
    relay.onEvent(
      NostrIdentity.sign(
        kind: recommendationKind,
        createdAt: 1760000000,
        tags: [
          ['d', recommendationDTag],
        ],
        content: jsonEncode({
          'v': recommendationVersion,
          'i': [
            [
              'hongguo',
              'hongguo:1',
              '别人的推荐',
              'https://img.example.com/1.jpg',
              '都市',
              1760000000,
            ],
          ],
        }),
        secretHex: other.secretHex,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('1 人'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-hongguo:1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

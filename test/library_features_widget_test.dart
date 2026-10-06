import 'dart:async';

import 'package:duanju_app/batch_download_screen.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/follow_state.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/saved_library.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_feature_fixtures.dart';

void main() {
  const first = LibraryFeatureRepository.first;
  const second = LibraryFeatureRepository.second;

  Future<LocalStore> create() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void viewport(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  WatchEntry watch(Drama drama) => WatchEntry(
    drama: drama,
    episode: 1,
    position: 12,
    duration: 60,
    updatedAt: DateTime.utc(2026, 9, 21),
  );

  testWidgets(
    'history searches locally and deletes one entry while preserving its manual mark',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await create();
      final repository = LibraryFeatureRepository();
      await store.saveWatch(watch(first));
      await store.saveWatch(watch(second));
      await store.setFollowStatus(first, FollowStatus.watched);
      final continued = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedLibrary(
              repository: repository,
              store: store,
              history: true,
              onOpen: (_) {},
              onContinue: (drama) => continued.add(drama.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('history-search')),
        '一号',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('saved-${first.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('saved-${second.id}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('continue-watching')));
      expect(continued, [first.id]);
      await tester.tap(find.byKey(ValueKey('drama-actions-${first.id}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除这条观看记录'));
      await tester.tap(find.text('删除这条观看记录'));
      await tester.pumpAndSettle();
      expect(store.history.single.drama.id, second.id);
      expect(store.following(first.id)!.manuallyWatched, isTrue);
      expect(repository.detailRequests, isEmpty);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'follow filters show unread updates until explicitly marked read',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await create();
      await store.setFollowStatus(first, FollowStatus.planned);
      await store.setFollowStatus(second, FollowStatus.watching);
      await store.refreshDrama(
        const Drama(
          id: 'hongguo:one',
          source: 'hongguo',
          title: '合成一号',
          episodes: 5,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedLibrary(
              repository: LibraryFeatureRepository(),
              store: store,
              history: false,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('follow-filter-updates'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('saved-${first.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('saved-${second.id}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('drama-actions-${first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标记 3 集更新已读'));
      await tester.pumpAndSettle();
      expect(store.following(first.id)!.newEpisodes, 0);
      expect(find.text('没有匹配的记录'), findsOneWidget);
      expect(store.history, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('series season notices appear in follow filters and detail', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    const seasonOne = Drama(
      id: 'hongguo:series-one',
      source: 'hongguo',
      title: '合成系列 第一季',
      episodes: 12,
    );
    const seasonTwo = Drama(
      id: 'hongguo:series-two',
      source: 'hongguo',
      title: '合成系列 第二季',
      episodes: 10,
    );
    final store = await create();
    await store.toggleFavorite(seasonOne);
    await store.refreshDramas([seasonOne, seasonTwo]);
    expect(store.following(seasonOne.id)!.newSeasons, 1);
    final repository = LibraryFeatureRepository()
      ..details[seasonOne.id] = LibraryFeatureRepository.makeDetail(
        seasonOne,
        12,
      )
      ..details[seasonTwo.id] = LibraryFeatureRepository.makeDetail(
        seasonTwo,
        10,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedLibrary(
            repository: repository,
            store: store,
            history: false,
            onOpen: (_) {},
            onContinue: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('follow-filter-updates')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('saved-${seasonOne.id}')), findsOneWidget);
    expect(find.textContaining('新季 1 部'), findsWidgets);
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: seasonOne,
          repository: repository,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('相关推荐'), findsOneWidget);
    expect(find.byKey(ValueKey('series-${seasonOne.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('series-${seasonTwo.id}')), findsOneWidget);
    final seasonTwoChip = find.byKey(ValueKey('series-${seasonTwo.id}'));
    await tester.ensureVisible(seasonTwoChip);
    await tester.tap(seasonTwoChip);
    await tester.pumpAndSettle();
    expect(store.following(seasonOne.id)!.newSeasons, 0);
    expect(find.text('合成系列 第二季'), findsWidgets);
    expect(repository.detailRequests, contains(seasonTwo.id));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('detail related series can use refreshed catalog candidates', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    const seasonOne = Drama(
      id: 'hongguo:plain-one',
      source: 'hongguo',
      title: '聚宝仙盆',
      episodes: 12,
    );
    const seasonTwo = Drama(
      id: 'hongguo:plain-two',
      source: 'hongguo',
      title: '聚宝仙盆 第二季',
      episodes: 10,
    );
    final store = await create();
    await store.refreshDramas([seasonOne, seasonTwo]);
    final repository = LibraryFeatureRepository()
      ..details[seasonOne.id] = LibraryFeatureRepository.makeDetail(
        seasonOne,
        12,
      )
      ..details[seasonTwo.id] = LibraryFeatureRepository.makeDetail(
        seasonTwo,
        10,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: seasonOne,
          repository: repository,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('相关推荐'), findsOneWidget);
    expect(find.byKey(ValueKey('series-${seasonTwo.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'home update uses a shared source job then reloads stale cache without another catalog request',
    (tester) async {
      viewport(tester, const Size(430, 844));
      final store = await create();
      await store.toggleFavorite(first);
      final repository = LibraryFeatureRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();
      final before = repository.requests.length;
      await tester.tap(find.byKey(const ValueKey('catalog-refresh')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('catalog-refresh')));
      expect(repository.starts, ['hongguo:update']);
      repository.cachedPages['hongguo'] = CatalogPage(
        [
          const Drama(
            id: 'hongguo:one',
            source: 'hongguo',
            title: '合成一号',
            episodes: 5,
          ),
          second,
          const Drama(id: 'hongguo:new', source: 'hongguo', title: '新发现的合成剧'),
        ],
        fresh: false,
        page: 4,
        hasMore: true,
      );
      repository.statuses['hongguo'] = repository.finished('hongguo');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      // 首页预加载会在空闲时接着缓存页往后补页，因此请求数不再固定；
      // 更新的不变式是「复用共享任务与磁盘缓存，不回头重取第一页」。
      expect(repository.pages, isNot(contains(1)));
      expect(repository.pages.skip(before), everyElement(greaterThan(1)));
      expect(find.text('新发现的合成剧'), findsOneWidget);
      expect(store.following(first.id)!.newEpisodes, 3);
      expect(
        tester
            .widget<RefreshAction>(
              find.byKey(const ValueKey('catalog-refresh')),
            )
            .loading,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'multi-selection previews all selected dramas before creating any download',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await create();
      final repository = LibraryFeatureRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-catalog-dramas')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(first.id)));
      await tester.tap(find.byKey(ValueKey(second.id)));
      await tester.pump();
      expect(find.text('已选 2 部'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('download-selected-dramas')));
      await tester.pumpAndSettle();
      expect(find.byType(BatchDownloadScreen), findsOneWidget);
      expect(repository.detailRequests, [first.id, second.id]);
      expect(repository.enqueues, isEmpty);
      await tester.tap(find.byKey(const ValueKey('submit-batch-downloads')));
      await tester.pumpAndSettle();
      expect(repository.enqueues.map((call) => call.$1), [first.id, second.id]);
      expect(repository.queued, hasLength(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'catalog card waits on home then opens player without launch page',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await create();
      final repository = LibraryFeatureRepository()
        ..pendingDetail = Completer<DramaDetail>();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(first.id)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('正在进入播放'), findsNothing);
      // 详情仍在请求中：播放按钮已渲染但处于禁用态，说明没有提前跳到播放器。
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-play')))
            .onPressed,
        isNull,
      );
      // 详情页压在首页之上，首页内容仍在（同名卡片/标题可能多处出现）。
      expect(find.text('合成一号'), findsWidgets);
      expect(repository.detailRequests, [first.id]);
      repository.pendingDetail!.complete(
        LibraryFeatureRepository.makeDetail(first, 2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(360, 640), const Size(1100, 720)]) {
    testWidgets('new library controls fit $size with large text', (
      tester,
    ) async {
      viewport(tester, size, scale: 1.8);
      final store = await create();
      await store.setFollowStatus(first, FollowStatus.planned);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedLibrary(
              repository: LibraryFeatureRepository(),
              store: store,
              history: false,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: BatchDownloadScreen(
            repository: LibraryFeatureRepository(),
            store: store,
            dramas: [first, second],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

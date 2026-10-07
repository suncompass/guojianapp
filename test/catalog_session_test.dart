import 'dart:async';

import 'package:duanju_app/catalog_browser.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class SessionRepository extends FixtureRepository {
  final catalogRequests = <String>[];
  final cacheRequests = <String>[];
  int coverRequests = 0;
  List<CatalogCategory> menu = const [
    CatalogCategory.all,
    CatalogCategory('comic', '漫剧'),
  ];
  bool fresh = true;
  String warning = '';
  Completer<void>? cancellation;
  Completer<CatalogPage>? pendingCategory;

  @override
  Future<void> cancelCatalog() => cancellation?.future ?? Future<void>.value();

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => menu;

  @override
  Future<String> cover(Drama drama, {bool force = false}) {
    coverRequests++;
    return super.cover(drama, force: force);
  }

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async {
    cacheRequests.add(category);
    return cachedPages['$source|$category'] ?? CatalogPage([]);
  }

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    catalogRequests.add('$category|$query|$page|$force');
    if (category == 'comic' && pendingCategory != null) {
      return pendingCategory!.future;
    }
    final label = query.isNotEmpty
        ? '搜索$query'
        : category.isEmpty
        ? '全部'
        : '漫剧';
    return CatalogPage(
      [
        // 首屏留足内容，避免首页的预加载调度干扰切换请求计数。
        for (var index = 0; index < 40; index++)
          Drama(
            id: '$source:$category:$query:$page:$index',
            source: source,
            title: '$label-$page-$index',
          ),
      ],
      page: page,
      hasMore: page < 3,
      fresh: fresh,
      warning: warning,
    );
  }
}

class CountingCatalogStore extends LocalStore {
  CountingCatalogStore(super.preferences);
  int catalogSyncs = 0;

  @override
  Future<void> refreshDramas(Iterable<Drama> dramas) {
    catalogSyncs++;
    return super.refreshDramas(dramas);
  }
}

void main() {
  const group = SourceGroup('hongguo', '红果', [SourceSite.hongguo]);

  test('切回全部同步复用已加载页，不重复读取且从原游标继续分页', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.loadCategories(group);
    await browser.load(group);
    final before = await browser.load(group, more: true);
    await browser.load(group, category: 'category:漫剧');
    final requests = repository.catalogRequests.length;
    final reads = repository.cacheRequests.length;
    final cancellation = repository.cancellation = Completer<void>();

    CatalogPage? immediate;
    final pending = browser.load(
      group,
      useCache: true,
      onCached: (page) => immediate = page,
    );
    // 即使取消旧请求尚未完成，也应在同一调用栈内恢复列表。
    expect(immediate, isNotNull);
    expect(immediate!.page, 2);
    expect(
      immediate!.items.map((item) => item.id),
      before.items.map((item) => item.id),
    );
    expect(repository.catalogRequests.length, requests);
    expect(repository.cacheRequests.length, reads);
    cancellation.complete();
    await pending;
    repository.cancellation = null;
    expect(repository.catalogRequests.length, requests);
    expect(repository.cacheRequests.length, reads);

    final more = await browser.load(group, more: true);
    expect(repository.catalogRequests.last, '||3|false');
    expect(more.items.length, 120);
    expect(more.hasMore, isFalse);
  });

  test('内存恢复使用独立回调，并且只构造一次快照', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.load(group);
    final cancellation = repository.cancellation = Completer<void>();
    CatalogPage? restored;
    var cacheCalls = 0;
    var restoreCalls = 0;
    final pending = browser.load(
      group,
      useCache: true,
      onCached: (_) => cacheCalls++,
      onRestored: (page) {
        restoreCalls++;
        restored = page;
      },
    );
    expect(restored, isNotNull);
    expect(restoreCalls, 1);
    expect(cacheCalls, 0);
    cancellation.complete();
    expect(await pending, same(restored));
    expect(restoreCalls, 1);
    expect(cacheCalls, 0);
  });

  test('分类缓存复用菜单，剧库、元数据、远端菜单变化后失效', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.loadCategories(group);
    final before = browser.categories(group);
    expect(browser.categories(group)[1], same(before[1]));
    // 分组名称相同但实际站源不同，不能命中已撤销站源的分类。
    expect(browser.categories(const SourceGroup('hongguo', '红果', [])), [
      CatalogCategory.all,
    ]);

    repository.cachedPages['hongguo|'] = CatalogPage(const [
      Drama(
        id: 'hongguo:cached',
        source: 'hongguo',
        title: '缓存剧集',
        category: '都市',
      ),
    ], fresh: true);
    await browser.load(group, cacheOnly: true);
    expect(
      browser.categories(group).map((category) => category.id),
      contains('local:都市'),
    );
    browser.updateDrama(
      const Drama(
        id: 'hongguo:cached',
        source: 'hongguo',
        title: '缓存剧集',
        category: '逆袭',
      ),
    );
    final updated = browser.categories(group);
    expect(updated.map((category) => category.id), contains('local:逆袭'));
    expect(updated.map((category) => category.id), isNot(contains('local:都市')));
    expect(browser.categories(group).last, same(updated.last));

    repository.cachedPages.clear();
    repository.menu = const [
      CatalogCategory.all,
      CatalogCategory('real', '真人剧'),
    ];
    await browser.loadCategories(group, force: true);
    final refreshed = browser.categories(group).map((category) => category.id);
    expect(refreshed, contains('category:真人剧'));
    expect(refreshed, isNot(contains('category:漫剧')));
    expect(refreshed, contains('local:逆袭'));
  });

  test('手动刷新和缓存同步不被已有会话快照拦截', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.load(group);
    CatalogPage? immediate;
    final refresh = browser.load(
      group,
      useCache: true,
      force: true,
      onCached: (page) => immediate = page,
    );
    expect(immediate, isNull);
    await refresh;
    expect(repository.catalogRequests.last, '||1|true');

    repository.cachedPages['hongguo|'] = CatalogPage(const [
      Drama(id: 'hongguo:updated', source: 'hongguo', title: '更新后的剧库'),
    ], fresh: true);
    final requests = repository.catalogRequests.length;
    final updated = await browser.load(group, cacheOnly: true, useCache: true);
    expect(repository.cacheRequests, ['']);
    expect(repository.catalogRequests.length, requests);
    expect(updated.items.single.id, 'hongguo:updated');
    final restored = await browser.load(group, useCache: true);
    expect(restored.items.single.id, 'hongguo:updated');
  });

  for (final state in [(false, ''), (true, '部分结果加载失败')]) {
    test('过期或有警告的结果仍走原来的重试流程：$state', () async {
      final repository = SessionRepository()
        ..fresh = state.$1
        ..warning = state.$2;
      final browser = CatalogBrowser(repository);
      await browser.load(group);
      repository.fresh = true;
      repository.warning = '';
      CatalogPage? immediate;
      final pending = browser.load(
        group,
        useCache: true,
        onCached: (page) => immediate = page,
      );
      expect(immediate, isNull);
      final result = await pending;
      expect(repository.cacheRequests, ['']);
      expect(repository.catalogRequests, ['||1|false', '||1|false']);
      expect(result.warning, isEmpty);
      expect(result.fresh, isTrue);
    });
  }

  test('搜索与全部会话隔离，搜索不会误命中分类快照', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    final all = await browser.load(group);
    await browser.load(group, query: '测试');
    CatalogPage? immediate;
    final search = browser.load(
      group,
      query: '测试',
      useCache: true,
      onCached: (page) => immediate = page,
    );
    expect(immediate, isNull);
    final result = await search;
    expect(result.items.first.title, '搜索测试-1-0');
    expect(repository.catalogRequests, ['||1|false', '|测试|1|false']);
    final restored = browser.load(
      group,
      useCache: true,
      onCached: (page) => immediate = page,
    );
    expect(immediate!.items.first.id, all.items.first.id);
    await restored;
  });

  test('切回快照仍包含最新元数据，不创建独立的陈旧列表副本', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    final page = await browser.load(group);
    browser.updateDrama(
      Drama(
        id: page.items.first.id,
        source: 'hongguo',
        title: '更新后的标题',
        cover: 'https://example.test/updated.jpg',
      ),
    );
    CatalogPage? immediate;
    final restored = browser.load(
      group,
      useCache: true,
      onCached: (page) => immediate = page,
    );
    expect(immediate!.items.first.title, '更新后的标题');
    expect(immediate!.items.first.cover, 'https://example.test/updated.jpg');
    await restored;
  });

  test('切回全部后，旧分类迟到的结果不能污染会话', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.loadCategories(group);
    final all = await browser.load(group);
    final category = repository.pendingCategory = Completer<CatalogPage>();
    final pending = browser.load(group, category: 'category:漫剧');
    await Future<void>.delayed(Duration.zero);
    expect(repository.catalogRequests.last, 'comic||1|false');

    final restored = await browser.load(group, useCache: true);
    expect(restored.items.first.id, all.items.first.id);
    category.complete(
      CatalogPage(const [
        Drama(id: 'hongguo:late', source: 'hongguo', title: '迟到的旧结果'),
      ], fresh: true),
    );
    await pending;
    repository.pendingCategory = null;
    final next = await browser.load(
      group,
      category: 'category:漫剧',
      useCache: true,
    );
    expect(next.items.any((item) => item.id == 'hongguo:late'), isFalse);
    expect(repository.catalogRequests, [
      '||1|false',
      'comic||1|false',
      'comic||1|false',
    ]);
  });

  test('等待取消时再次切换，旧的快照加载仍按代次作废', () async {
    final repository = SessionRepository();
    final browser = CatalogBrowser(repository);
    await browser.load(group);
    final cancellation = repository.cancellation = Completer<void>();
    final pending = browser.load(group, useCache: true);
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    final newer = browser.load(group, useCache: true);
    cancellation.complete();
    await rejected;
    await newer;
    expect(repository.catalogRequests, ['||1|false']);
  });

  testWidgets('底部页签往返主页保留滚动树和封面，不重复加载目录', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await store.setSource('hongguo');
    final repository = SessionRepository();
    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final position = scroll.controller!.position;
    scroll.controller!.jumpTo(300);
    await tester.pumpAndSettle();
    final tile = tester.element(find.byType(DramaTile).first);
    final tileKey = tile.widget.key!;
    final requests = repository.catalogRequests.length;
    final reads = repository.cacheRequests.length;
    final covers = repository.coverRequests;

    for (final tab in [1, 2, 3]) {
      await tester.tap(find.byKey(ValueKey('bottom-nav-$tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(tileKey), findsNothing);
      expect(
        tester.element(find.byKey(tileKey, skipOffstage: false)),
        same(tile),
      );
      expect(scroll.controller!.position, same(position));
      expect(position.pixels, 300);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-0')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byKey(tileKey)), same(tile));
      expect(scroll.controller!.position, same(position));
      expect(position.pixels, 300);
      expect(repository.catalogRequests.length, requests);
      expect(repository.cacheRequests.length, reads);
      expect(repository.coverRequests, covers);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    // 隐藏目录仍然挂载，但滚动通知不能触发后台续页或恢复预取。
    scroll.controller!.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.catalogRequests.length, requests);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首页切回全部不闪加载动画，也不重复读取已加载列表', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = CountingCatalogStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await store.setSource('hongguo');
    final repository = SessionRepository();
    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-category:漫剧')));
    await tester.pumpAndSettle();
    expect(find.text('漫剧-1-0'), findsOneWidget);
    final syncs = store.catalogSyncs;
    expect(syncs, greaterThan(0));
    final requests = repository.catalogRequests.length;
    final reads = repository.cacheRequests.length;
    final cancellation = repository.cancellation = Completer<void>();

    await tester.tap(find.byKey(const ValueKey('category-')));
    await tester.pump();
    expect(find.text('全部-1-0'), findsOneWidget);
    expect(find.text('正在加载剧集'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(store.catalogSyncs, syncs, reason: '内存恢复不应重复合并和保存整库');
    expect(repository.catalogRequests.length, requests);
    expect(repository.cacheRequests.length, reads);
    cancellation.complete();
    await tester.pumpAndSettle();
    repository.cancellation = null;
    expect(store.catalogSyncs, syncs, reason: '取消完成后不能再同步一次相同快照');
    await tester.tap(find.byKey(const ValueKey('category-')));
    await tester.pumpAndSettle();
    expect(repository.catalogRequests.length, requests);
    expect(repository.cacheRequests.length, reads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

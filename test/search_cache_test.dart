import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/search_cache.dart';

Drama drama(String title, String source) => Drama(
  id: '$source:$title',
  title: title,
  source: source,
  episodes: 1,
  cover: '',
);

void main() {
  setUp(() => SearchResultCache.instance.clear());

  test('cache reuse prefers the exact query', () {
    final cache = SearchResultCache.instance;
    cache.writeItems(
      source: 'hongguo',
      query: '与狼共吻',
      items: [drama('与狼共吻', 'hongguo')],
      total: 1,
    );
    cache.writeItems(
      source: 'hongguo',
      query: '聚宝仙盆',
      items: [drama('聚宝仙盆', 'hongguo')],
      total: 1,
    );
    expect(cache.read('hongguo', '聚宝仙盆')?.query, '聚宝仙盆');
  });

  test('readAnyQuery can reject unrelated cached queries', () {
    final cache = SearchResultCache.instance;
    cache.writeItems(
      source: 'hongguo',
      query: '与狼共吻',
      items: [drama('与狼共吻', 'hongguo')],
      total: 1,
    );
    final unrelated = cache.readAnyQuery(
      'hongguo',
      where: (entry) => entry.query.contains('聚宝仙盆'),
    );
    expect(unrelated, isNull);
    final related = cache.readAnyQuery(
      'hongguo',
      where: (entry) => entry.query.contains('与狼共吻'),
    );
    expect(related?.query, '与狼共吻');
  });

  test('a cached query is not reused across sources', () {
    final cache = SearchResultCache.instance;
    cache.writeItems(
      source: 'hongguo',
      query: '聚宝仙盆',
      items: [drama('聚宝仙盆', 'hongguo')],
      total: 1,
    );
    expect(cache.readAnyQuery('xingguo'), isNull);
  });

  test('cached items whose titles match the keyword survive filtering', () {
    final cache = SearchResultCache.instance;
    cache.writeItems(
      source: 'hongguo',
      query: '聚宝仙盆',
      items: [drama('聚宝仙盆', 'hongguo'), drama('聚宝仙盆 第二季', 'hongguo')],
      total: 2,
    );
    final entry = cache.read('hongguo', '聚宝仙盆');
    expect(entry?.items.length, 2);
    expect(entry?.complete, isTrue);
  });

  test('expired results remain available for display during a refresh', () {
    final cache = SearchResultCache.instance;
    final entry = SearchCacheEntry(
      source: 'hongguo',
      query: '测试短剧',
      items: [drama('测试短剧', 'hongguo')],
      total: 1,
      storedAt: DateTime.now().subtract(const Duration(minutes: 21)),
    );
    cache.write(entry);
    expect(entry.fresh, isFalse);
    expect(cache.read('hongguo', '测试短剧'), isNull);
    expect(cache.readAnyQuery('hongguo'), isNull);
    expect(cache.read('hongguo', '测试短剧', allowStale: true), same(entry));
    expect(cache.readAnyQuery('hongguo', allowStale: true), same(entry));
  });

  test('a completed refresh replaces metadata and renews the expiry', () {
    final cache = SearchResultCache.instance;
    final old = SearchCacheEntry(
      source: 'hongguo',
      query: '测试短剧',
      items: [drama('测试短剧', 'hongguo')],
      total: 1,
      storedAt: DateTime.now().subtract(const Duration(minutes: 21)),
    );
    cache.write(old);
    cache.writeItems(
      source: 'hongguo',
      query: '测试短剧',
      items: [drama('测试短剧 更新', 'hongguo')],
    );
    final refreshed = cache.read('hongguo', '测试短剧');
    expect(refreshed?.items.single.title, '测试短剧 更新');
    expect(refreshed?.fresh, isTrue);
    expect(refreshed!.storedAt.isAfter(old.storedAt), isTrue);
  });

  test(
    'empty successful results are cached but failed refreshes preserve data',
    () {
      final cache = SearchResultCache.instance;
      cache.writeItems(
        source: 'hongguo',
        query: '测试短剧',
        items: [drama('测试短剧', 'hongguo')],
      );
      final saved = cache.read('hongguo', '测试短剧');
      cache.writeItems(
        source: 'hongguo',
        query: '测试短剧',
        items: [],
        warning: '合成网络错误',
      );
      expect(cache.read('hongguo', '测试短剧'), same(saved));
      cache.writeItems(source: 'hongguo', query: '测试短剧', items: []);
      expect(cache.read('hongguo', '测试短剧')?.items, isEmpty);
      expect(cache.read('hongguo', '测试短剧')?.fresh, isTrue);
    },
  );

  test('equivalent in-flight queries share one request', () async {
    final cache = SearchResultCache.instance;
    final pending = Completer<SearchCacheEntry>();
    var calls = 0;
    Future<SearchCacheEntry> load() {
      calls++;
      return pending.future;
    }

    final first = cache.coalesce('hongguo', '测试 短剧', load);
    final second = cache.coalesce('hongguo', '测试短剧', load);
    expect(calls, 1);
    expect(second, same(first));
    pending.complete(
      SearchCacheEntry(source: 'hongguo', query: '测试短剧', items: [], total: 0),
    );
    await Future.wait([first, second]);
    await cache.coalesce('hongguo', '测试短剧', load);
    expect(calls, 2);
  });

  test('search results survive cache reinitialization', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final cache = SearchResultCache.instance;
    await cache.initialize(preferences);
    cache.writeItems(
      source: 'huangguoai',
      query: '一个乖乖女',
      items: [drama('一个乖乖女', 'huangguoai')],
      total: 1,
    );
    await cache.flush();
    await cache.initialize(preferences);
    expect(cache.read('huangguoai', '一个乖乖女')?.items.single.title, '一个乖乖女');
  });
}

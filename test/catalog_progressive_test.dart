import 'dart:async';

import 'package:duanju_app/catalog_browser.dart';
import 'package:duanju_app/catalog_sort.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class SlowRepository extends FixtureRepository {
  final completers = <String, Completer<CatalogPage>>{};
  final started = <String>[];

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage(const []);

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) {
    started.add(source);
    return (completers[source] ??= Completer<CatalogPage>()).future;
  }

  @override
  Future<void> cancelCatalog() async {}
}

Drama drama(String source, int index) => Drama(
  id: '$source:$index',
  source: source,
  title: '$source 剧集 $index',
  episodes: 10,
);

void main() {
  test('searchKeyword strips seasons, episode counts and noise', () {
    expect(searchKeyword('冒姓琅琊'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 第二季'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊第2季'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊（第二部）'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 全集'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 80集'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 全80集'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊·大结局'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 4K 高清'), '冒姓琅琊');
    expect(searchKeyword('冒姓琅琊 第三季 抢先版'), '冒姓琅琊');
    expect(searchKeyword('   '), '');
    expect(searchKeyword(''), '');
  });

  test('searchKeyword keeps titles that only contain digits', () {
    expect(searchKeyword('749局'), '749局');
    expect(searchKeyword('灿烂的'), '灿烂的');
  });

  test('naturalTitleCompare sorts Chinese numerals correctly', () {
    final titles = ['剧 第十季', '剧 第二季', '剧 第一季'];
    titles.sort(naturalTitleCompare);
    expect(titles, ['剧 第一季', '剧 第二季', '剧 第十季']);
  });

  test('partial results stream before slower sources finish', () async {
    final repository = SlowRepository();
    final browser = CatalogBrowser(repository);
    final group = SourceGroup('fixture', '合成站源', [
      const SourceSite('alpha', '甲', '合成'),
      const SourceSite('beta', '乙', '合成'),
    ]);
    final partials = <int>[];
    final pending = browser.load(
      group,
      onPartial: (page) => partials.add(page.items.length),
    );
    await Future<void>.delayed(Duration.zero);
    repository.completers['alpha']!.complete(
      CatalogPage([drama('alpha', 1), drama('alpha', 2)]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(partials, isNotEmpty);
    expect(partials.first, 2);
    repository.completers['beta']!.complete(CatalogPage([drama('beta', 1)]));
    final result = await pending;
    expect(result.items.length, 3);
    expect(partials.last, lessThanOrEqualTo(result.items.length));
  });

  test('search results stream progressively too', () async {
    final repository = SlowRepository();
    final browser = CatalogBrowser(repository);
    final group = SourceGroup('fixture', '合成站源', [
      const SourceSite('alpha', '甲', '合成'),
    ]);
    final partials = <int>[];
    final pending = browser.load(
      group,
      query: '冒姓琅琊',
      onPartial: (page) => partials.add(page.items.length),
    );
    await Future<void>.delayed(Duration.zero);
    repository.completers['alpha']!.complete(CatalogPage([drama('alpha', 1)]));
    final result = await pending;
    expect(partials, isNotEmpty);
    expect(result.items.length, 1);
  });
}

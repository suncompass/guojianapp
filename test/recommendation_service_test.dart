import 'dart:convert';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/nostr_crypto.dart';
import 'package:duanju_app/nostr_relay.dart';
import 'package:duanju_app/recommendation_models.dart';
import 'package:duanju_app/recommendation_service.dart';
import 'package:duanju_app/recommendation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只记录调用、不联网的 relay 替身。
class _FakeRelay extends NostrRelayPool {
  _FakeRelay(
    super.relays, {
    required super.onEvent,
    super.onStatus,
    super.onNotice,
  });

  final published = <NostrEvent>[];
  var accept = 1;

  @override
  void start({
    required int kind,
    required String dTag,
    String subscription = 'zhenguo-feed',
  }) {
    onStatus?.call();
  }

  @override
  Future<int> publish(NostrEvent event) async {
    published.add(event);
    return accept;
  }

  @override
  int get connected => accept > 0 ? 1 : 0;

  @override
  int get total => 1;

  @override
  Future<void> dispose() async {}

  RecommendationVector? lastVector() =>
      published.isEmpty ? null : decodeVectorEvent(published.last);
}

Drama _drama({
  String id = 'hongguo:1',
  String title = '都市逆袭',
  String source = 'hongguo',
  String cover = 'https://img.example.com/a.jpg',
  String category = '都市',
}) => Drama(
  id: id,
  source: source,
  title: title,
  cover: cover,
  category: category,
);

WatchEntry _watch(
  Drama drama, {
  required int episode,
  required double position,
  double duration = 60,
}) => WatchEntry(
  drama: drama,
  episode: episode,
  position: position,
  duration: duration,
  updatedAt: DateTime.now(),
);

void main() {
  late SharedPreferences preferences;
  late LocalStore store;
  late _FakeRelay relay;

  Future<RecommendationService> attach({
    Duration publishDelay = const Duration(milliseconds: 20),
  }) async {
    final service = RecommendationService(
      preferences,
      publishDelay: publishDelay,
      watchSaveDelay: const Duration(milliseconds: 10),
      relayFactory: (relays, onEvent, onStatus, onNotice) => relay = _FakeRelay(
        relays,
        onEvent: onEvent,
        onStatus: onStatus,
        onNotice: onNotice,
      ),
    );
    RecommendationService.current = service;
    service.attach(store);
    return service;
  }

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

  test('首次进入会生成本机身份并保存', () async {
    final service = await attach();
    expect(service.shortIdentity, isNot('未就绪'));
    final saved = RecommendationStore(preferences).identity(store.profile.id);
    expect(saved, isNotNull);
    expect(saved, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      NostrIdentity.publicKeyOf(saved!),
      startsWith(service.shortIdentity),
    );
    // 再次进入沿用同一个身份
    service.detach();
    final again = await attach();
    expect(again.shortIdentity, service.shortIdentity);
  });

  test('累计观看不足时不会发布', () async {
    final service = await attach();
    final drama = _drama();
    for (var second = 5; second <= 60; second += 5) {
      service.observe(_watch(drama, episode: 1, position: second.toDouble()));
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(relay.published, isEmpty);
    expect(service.myCount, 0);
  });

  test('累计有效观看达到 10 分钟后自动发布', () async {
    final service = await attach();
    final drama = _drama();
    // 单集长剧：只看时长这一条规则也能达标。
    for (var second = 5; second <= 610; second += 5) {
      service.observe(
        _watch(drama, episode: 1, position: second.toDouble(), duration: 3600),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.myCount, 1);
    expect(relay.published, hasLength(1));
    final vector = relay.lastVector();
    expect(vector, isNotNull);
    expect(vector!.items.single.id, drama.id);
    expect(vector.items.single.source, 'hongguo');
    expect(vector.items.single.title, '都市逆袭');
    expect(service.items.single.recommenders, 1);
    expect(service.items.single.mine, isTrue);
  });

  test('连续看完 5 集同样会进入动态', () async {
    final service = await attach();
    final drama = _drama();
    for (var episode = 1; episode <= 5; episode++) {
      service.observe(_watch(drama, episode: episode, position: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.myCount, 1);
  });

  test('删除自己的记录会重新发布并重新计时', () async {
    final service = await attach();
    final drama = _drama();
    for (var episode = 1; episode <= 5; episode++) {
      service.observe(_watch(drama, episode: episode, position: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.items, hasLength(1));

    await service.remove(drama.id);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.myCount, 0);
    expect(service.items, isEmpty);
    expect(relay.lastVector()!.items, isEmpty);
    expect(service.watchedMsFor(drama.id), 0);

    // 重新看一集不足以再次发布
    service.observe(_watch(drama, episode: 1, position: 60));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(service.myCount, 0);
  });

  test('多选删除只撤下选中的记录，未选中的继续保留', () async {
    final service = await attach();
    final first = _drama(id: 'hongguo:1', title: '都市逆袭');
    final second = _drama(id: 'hongguo:2', title: '重生归来');
    final third = _drama(id: 'hongguo:3', title: '深夜食堂');
    for (final drama in [first, second, third]) {
      for (var episode = 1; episode <= 5; episode++) {
        service.observe(_watch(drama, episode: episode, position: 60));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.myCount, 3);
    expect(service.myEntries.map((entry) => entry.id), [
      'hongguo:3',
      'hongguo:2',
      'hongguo:1',
    ]);

    await service.removeMany([first.id, third.id]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.myCount, 1);
    expect(service.myEntries.single.id, second.id);
    final vector = relay.lastVector();
    expect(vector, isNotNull);
    expect(vector!.items.map((item) => item.id), [second.id]);
    expect(service.watchedMsFor(first.id), 0);
    expect(service.watchedMsFor(third.id), 0);

    // 被删除的剧重新看一集不足以再次发布，未删除的仍然保留。
    service.observe(_watch(first, episode: 1, position: 60));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(service.myEntries.single.id, second.id);
  });

  test('多选删除空集合与未知 ID 都不改变发布内容', () async {
    final service = await attach();
    final drama = _drama();
    for (var episode = 1; episode <= 5; episode++) {
      service.observe(_watch(drama, episode: episode, position: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final published = relay.published.length;

    await service.removeMany(const <String>[]);
    await service.removeMany(['hongguo:missing', '']);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.myCount, 1);
    expect(relay.published, hasLength(published));
  });

  test('隐藏只影响本机显示', () async {
    final service = await attach();
    final drama = _drama();
    for (var episode = 1; episode <= 5; episode++) {
      service.observe(_watch(drama, episode: episode, position: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.items, hasLength(1));
    await service.hide(drama.id);
    expect(service.items, isEmpty);
    expect(service.hiddenCount, 1);
    await service.restoreHidden();
    expect(service.items, hasLength(1));
  });

  test('发布的列表在本机立即可见，relay 断线时记为待补发', () async {
    final service = await attach();
    relay.accept = 0;
    final drama = _drama();
    for (var episode = 1; episode <= 5; episode++) {
      service.observe(_watch(drama, episode: episode, position: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(service.items, hasLength(1));
    expect(service.pendingPublish, isTrue);
    expect(service.notice, isNotEmpty);
  });

  test('其他用户的推荐会进入榜单', () async {
    final service = await attach();
    final other = NostrIdentity.generate();
    final event = NostrIdentity.sign(
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
            'hongguo:9',
            '别人的推荐',
            'https://img.example.com/9.jpg',
            '古装',
            1760000000,
          ],
        ],
      }),
      secretHex: other.secretHex,
    );
    relay.onEvent(event);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(service.items, hasLength(1));
    expect(service.items.single.title, '别人的推荐');
    expect(service.items.single.mine, isFalse);
    expect(service.items.single.recommendLabel, '1 人');

    // 同一事件重复到达不会重复计数
    relay.onEvent(event);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(service.items.single.recommenders, 1);
  });

  test('站源与分类筛选', () async {
    final service = await attach();
    final other = NostrIdentity.generate();
    final event = NostrIdentity.sign(
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
            'hongguo:9',
            '都市剧',
            'https://img.example.com/9.jpg',
            '都市',
            1760000000,
          ],
          [
            'hongguo',
            'hongguo:8',
            '古装剧',
            'https://img.example.com/8.jpg',
            '古装',
            1760000000,
          ],
        ],
      }),
      secretHex: other.secretHex,
    );
    relay.onEvent(event);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(
      service.sourceChoices.map((row) => row.id),
      containsAll(<String>[recommendationAllSources, 'hongguo']),
    );
    expect(
      service.categoryChoices.map((row) => row.id),
      containsAll(<String>['都市', '古装']),
    );

    service.toggleSource('hongguo');
    expect(service.selectedSources, {'hongguo'});
    expect(service.items, hasLength(2));

    service.toggleSource(recommendationAllSources);
    expect(service.selectedSources, isEmpty);
    expect(service.items, hasLength(2));

    service.setCategoryFilter('古装');
    expect(service.items.map((row) => row.id), ['hongguo:8']);
    service.setCategoryFilter('古装');
    expect(service.items, hasLength(2));
  });

  test('内置屏蔽的发布者不出现在榜单里', () async {
    final service = await attach();
    expect(service.blockedCount, 1);
    final seeded = recommendationSeededBlocks.single;
    relay.onEvent(
      NostrEvent(
        id: 'a' * 64,
        pubkey: seeded,
        createdAt: 1790941140,
        kind: recommendationKind,
        tags: [
          ['d', recommendationDTag],
        ],
        content: jsonEncode({
          'v': recommendationVersion,
          'i': [
            [
              'hongguo',
              'hongguo:verify',
              '验证用剧名',
              'https://example.com/a.jpg',
              '都市',
              1760000000,
            ],
          ],
        }),
        sig: 'b' * 128,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(service.allItems.any((row) => row.title == '验证用剧名'), isFalse);
    expect(service.items, isEmpty);

    await service.restoreBlocked();
    expect(
      service.allItems.single.title,
      '验证用剧名',
      reason: '解除屏蔽后应能看到这条记录，说明屏蔽是这一层生效的',
    );
  });

  test('屏蔽发布者后其推荐立即消失，恢复后重新出现', () async {
    final service = await attach();
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
              'hongguo:9',
              '别人的剧',
              'https://img.example.com/9.jpg',
              '都市',
              1760000000,
            ],
          ],
        }),
        secretHex: other.secretHex,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(service.items, hasLength(1));
    expect(service.items.single.publishers, {other.publicKey});

    await service.blockPublisher(other.publicKey);
    expect(service.items, isEmpty);
    expect(service.allItems, isEmpty);
    expect(service.blockedCount, 2);
    expect(service.blockedPublisher(other.publicKey), isTrue);

    await service.restoreBlocked();
    expect(service.items, hasLength(1));
    expect(service.blockedCount, 0);
  });

  test('站源可多选，全部与具体站源互斥', () async {
    final service = await attach();
    final available = SourceSite.values.toList();
    final used = available.take(2).toList();
    for (final site in used) {
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
                site.id,
                '${site.id}:9',
                '${site.name}剧',
                'https://img.example.com/9.jpg',
                '都市',
                1760000000,
              ],
            ],
          }),
          secretHex: other.secretHex,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(service.items, hasLength(used.length));

    final first = used.first;
    service.toggleSource(first.id);
    expect(service.selectedSources, {first.id});
    expect(service.items.map((row) => row.id), ['${first.id}:9']);

    service.toggleSource(recommendationAllSources);
    expect(service.selectedSources, isEmpty);
    expect(service.items, hasLength(used.length));

    if (used.length < 2) return;
    final second = used[1];
    service.toggleSource(first.id);
    service.toggleSource(second.id);
    expect(service.selectedSources, {first.id, second.id});
    expect(service.items.map((row) => row.id).toSet(), {
      '${first.id}:9',
      '${second.id}:9',
    });

    service.toggleSource(first.id);
    expect(service.selectedSources, {second.id});
    expect(service.items.map((row) => row.id), ['${second.id}:9']);

    service.toggleSource(second.id);
    expect(service.selectedSources, isEmpty, reason: '取消最后一个站源等于回到全部');
    expect(service.items, hasLength(used.length));
  });
}

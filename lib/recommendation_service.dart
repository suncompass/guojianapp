import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_browser.dart';
import 'local_store.dart';
import 'models.dart';
import 'nostr_crypto.dart';
import 'nostr_relay.dart';
import 'recommendation_models.dart';
import 'recommendation_store.dart';

/// 动态页连接的 relay 列表，与 `../nostr` 使用同一组公共 relay。
const List<String> recommendationRelays = [
  'wss://kotukonostr.onrender.com',
  'wss://nostr.spicyz.io',
  'wss://x.kojira.io',
  'wss://relay.wellorder.net',
  'wss://relay-sgp.signedbyme.com',
];

/// 站源筛选里代表「全部站源」的标识，与任何具体站源互斥。
const String recommendationAllSources = 'all';

/// 「在看」默认只看这个站源，用户改过筛选后不再覆盖。
const String recommendationDefaultSource = 'hongguo';

/// 内置屏蔽的发布者：2026-10-02 联调 relay 时用一次性随机身份发布过一条
/// 「验证用剧名」的合成记录，私钥没有留存，relay 按 NIP-09 只接受同一私钥的删除，
/// 因此无法从 relay 上撤下，只能在这一层屏蔽该发布者。
const Set<String> recommendationSeededBlocks = {
  '20d0e5c7681b570b9629395655d005975edd7fde39267f3168a637a0870500f2',
};

/// 观看达到这个时长（或看完这么多集）才算「看过」，自动进入动态。
///
/// 参考 `nostr.html` 观影偏好同步页面的 `WATCH_HEAT_MS`（10 分钟），短剧单集较短，
/// 因此补一条等效的集数门槛：连续看完 5 集同样视为有效观看，避免只看了几集长剧的用户
/// 永远进不了动态。
const int recommendationMinWatchMs = 10 * 60 * 1000;
const int recommendationMinEpisodes = 5;

/// 单次进度回报最多累计的秒数，用于排除拖动进度条造成的时间跳变。
const double recommendationMaxSampleSeconds = 20;

typedef NostrRelayFactory =
    NostrRelayPool Function(
      List<String> relays,
      void Function(NostrEvent event) onEvent,
      void Function() onStatus,
      void Function(String message) onNotice,
    );

NostrRelayPool _createRelayPool(
  List<String> relays,
  void Function(NostrEvent event) onEvent,
  void Function() onStatus,
  void Function(String message) onNotice,
) => NostrRelayPool(
  relays,
  onEvent: onEvent,
  onStatus: onStatus,
  onNotice: onNotice,
);

class RecommendationService extends ChangeNotifier {
  RecommendationService(
    this.preferences, {
    NostrRelayFactory? relayFactory,
    this.publishDelay = const Duration(seconds: 2),
    this.watchSaveDelay = const Duration(seconds: 15),
  }) : _store = RecommendationStore(preferences),
       _relayFactory = relayFactory ?? _createRelayPool;

  static RecommendationService? current;

  static const publishRetryDelay = Duration(seconds: 20);
  static const rebuildDelay = Duration(milliseconds: 160);
  static const maxVectors = 4000;

  final Duration publishDelay;
  final Duration watchSaveDelay;

  final SharedPreferences preferences;
  final RecommendationStore _store;
  final NostrRelayFactory _relayFactory;

  LocalStore? _local;
  String _profile = 'default';
  NostrIdentity? _identity;
  NostrRelayPool? _pool;
  final Map<String, RecommendationVector> _vectors = {};
  List<RecommendationEntry> _mine = [];
  Map<String, RecommendationWatch> _watch = {};
  Set<String> _hidden = {};
  Set<String> _blocked = {};
  Set<String> _sources = {};
  String _sourceFocus = recommendationAllSources;
  String _categoryFilter = '';
  int _publishedAt = 0;
  bool _pendingPublish = false;
  bool _publishing = false;
  bool _attached = false;
  String _notice = '';
  List<FeedItem> _feed = const [];
  List<FeedItem> _visible = const [];
  List<CatalogCategory> _categoryChoices = const [];
  Timer? _publishTimer;
  Timer? _retryTimer;
  Timer? _watchTimer;
  Timer? _rebuildTimer;
  bool _watchDirty = false;

  bool get attached => _attached;
  String get profile => _profile;
  String get shortIdentity {
    final key = _identity?.publicKey ?? '';
    return key.isEmpty ? '未就绪' : key.substring(0, 8);
  }

  int get connected => _pool?.connected ?? 0;
  int get relayTotal => _pool?.total ?? recommendationRelays.length;
  Map<String, String> get relayStates => _pool?.states ?? const {};
  String get notice => _notice;
  bool get publishing => _publishing;
  bool get pendingPublish => _pendingPublish;
  int get myCount => _mine.length;
  List<RecommendationEntry> get myEntries => List.unmodifiable(_mine);
  List<FeedItem> get allItems => _feed;
  List<FeedItem> get items => _visible;
  Set<String> get selectedSources => _sources;
  String get sourceFocus => _sourceFocus;
  String get categoryFilter => _categoryFilter;
  List<CatalogCategory> get categoryChoices => _categoryChoices;

  List<CatalogCategory> get sourceChoices {
    final sources = _local?.sources ?? const <SourceSite>[];
    return [
      const CatalogCategory(recommendationAllSources, '全部'),
      for (final group in SourceGroup.fromSources(sources))
        CatalogCategory(group.id, group.name),
    ];
  }

  List<CatalogCategory> get categoryFilters => _categoryChoices;

  void attach(LocalStore store) {
    if (_attached && identical(_local, store) && _profile == store.profile.id) {
      return;
    }
    _teardown();
    _local = store;
    _profile = store.profile.id;
    var secret = _store.identity(_profile);
    if (secret == null) {
      final generated = NostrIdentity.generate();
      secret = generated.secretHex;
      unawaited(_store.setIdentity(_profile, secret));
    }
    _identity = NostrIdentity(secret);
    _mine = _store.items(_profile);
    _watch = _store.watch(_profile);
    _hidden = _store.hidden(_profile);
    _blocked = _store.blocked(_profile);
    if (!_store.seeded(_profile)) {
      _blocked = {..._blocked, ...recommendationSeededBlocks};
      unawaited(_store.setBlocked(_profile, _blocked));
      unawaited(_store.setSeeded(_profile, true));
    }
    final filter = _store.filter(_profile);
    if (filter.chosen) {
      _sources = filter.sources;
    } else {
      _sources = (store.allowsSource(recommendationDefaultSource))
          ? {recommendationDefaultSource}
          : <String>{};
    }
    _sourceFocus = _sources.isEmpty ? recommendationAllSources : _sources.last;
    _categoryFilter = filter.category;
    _publishedAt = _store.publishedAt(_profile);
    _pendingPublish = _store.pending(_profile);
    _attached = true;
    unawaited(
      _store.pruneProfiles({for (final item in store.profiles) item.id}),
    );
    _startPool();
    _rebuild();
    notifyListeners();
    if (_pendingPublish) _schedulePublish();
  }

  void detach() {
    if (!_attached) return;
    _teardown();
    _local = null;
    _attached = false;
    _feed = const [];
    _visible = const [];
    notifyListeners();
  }

  void _teardown() {
    _publishTimer?.cancel();
    _retryTimer?.cancel();
    _watchTimer?.cancel();
    _rebuildTimer?.cancel();
    _publishTimer = null;
    _retryTimer = null;
    _watchTimer = null;
    _rebuildTimer = null;
    _watchDirty = false;
    final pool = _pool;
    _pool = null;
    if (pool != null) unawaited(pool.dispose());
  }

  @override
  void dispose() {
    _teardown();
    if (identical(current, this)) current = null;
    super.dispose();
  }

  void _startPool() {
    final pool = _relayFactory(
      recommendationRelays,
      _onEvent,
      _onStatus,
      _onNotice,
    );
    _pool = pool;
    pool.start(
      kind: recommendationKind,
      dTag: recommendationDTag,
      subscription: 'zhenguo-feed',
    );
    notifyListeners();
  }

  Future<void> refresh() async {
    _notice = '';
    final pool = _pool;
    if (pool != null) {
      pool.start(
        kind: recommendationKind,
        dTag: recommendationDTag,
        subscription: 'zhenguo-feed',
      );
    }
    notifyListeners();
    if (_pendingPublish) {
      _schedulePublish(immediate: true);
    }
  }

  void toggleSource(String value) {
    final next = Set<String>.of(_sources);
    if (value == recommendationAllSources) {
      if (next.isEmpty) return;
      next.clear();
    } else if (!next.remove(value)) {
      next.add(value);
    }
    if (next.length == _sources.length && next.containsAll(_sources)) return;
    _sources = next;
    _sourceFocus = value;
    _categoryFilter = '';
    _applyFilters();
    _saveFilter();
    notifyListeners();
  }

  void setCategoryFilter(String value) {
    final next = _categoryFilter == value ? '' : value;
    if (_categoryFilter == next) return;
    _categoryFilter = next;
    _applyFilters();
    _saveFilter();
    notifyListeners();
  }

  void _saveFilter() {
    unawaited(
      _store.setFilter(_profile, sources: _sources, category: _categoryFilter),
    );
  }

  void clearNotice() {
    if (_notice.isEmpty) return;
    _notice = '';
    notifyListeners();
  }

  /// 观看进度回报：累计有效观看时长与已看完集数，达标后自动把自己的推荐发到动态。
  void observe(WatchEntry entry) {
    if (!_attached) return;
    final local = _local;
    if (local == null) return;
    final drama = entry.drama;
    if (!local.allowsSource(drama.source)) return;
    if (drama.id.isEmpty || drama.title.isEmpty) return;
    if (!drama.cover.startsWith('http')) return;
    final now = _nowSeconds();
    final state = _watch[drama.id] ??= RecommendationWatch(
      entry: RecommendationEntry.fromDrama(drama, at: 0),
    );
    state.entry = RecommendationEntry.fromDrama(drama, at: state.entry.at);
    final episode = entry.episode;
    if (state.lastEpisode == episode && state.lastPosition != null) {
      final delta = entry.position - state.lastPosition!;
      if (delta > 0 && delta <= recommendationMaxSampleSeconds) {
        state.watchedMs += (delta * 1000).round();
      }
    }
    state.lastEpisode = episode;
    state.lastPosition = entry.position;
    if (entry.finished) state.episodes.add(episode);
    state.updatedAt = now;
    if (!state.published && _qualifies(state)) {
      state.published = true;
      state.entry = RecommendationEntry.fromDrama(drama, at: now);
      _mine
        ..removeWhere((item) => item.id == drama.id)
        ..insert(0, state.entry);
      if (_mine.length > recommendationItemLimit) {
        _mine = _mine.sublist(0, recommendationItemLimit);
      }
      unawaited(_store.setItems(_profile, _mine));
      _markWatchDirty();
      _rebuild();
      notifyListeners();
      _schedulePublish();
      return;
    }
    _markWatchDirty();
  }

  bool _qualifies(RecommendationWatch state) =>
      state.watchedMs >= recommendationMinWatchMs ||
      state.episodes.length >= recommendationMinEpisodes;

  int watchedMsFor(String dramaId) => _watch[dramaId]?.watchedMs ?? 0;

  /// 删除自己发布的一条推荐，并重新计时，只有再次有效观看才会重新进入动态。
  Future<void> remove(String dramaId) => removeMany([dramaId]);

  /// 批量删除自己发布的推荐，供「我发布的记录」多选删除使用。
  Future<void> removeMany(Iterable<String> dramaIds) async {
    final ids = dramaIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    final removed = _mine.where((item) => ids.contains(item.id)).length;
    var watched = false;
    for (final id in ids) {
      if (_watch[id] == null) continue;
      watched = true;
      _watch[id]!.resetWatch();
    }
    if (removed == 0 && !watched) return;
    _mine.removeWhere((item) => ids.contains(item.id));
    await _store.setItems(_profile, _mine);
    _watchDirty = true;
    await _saveWatch();
    _rebuild();
    notifyListeners();
    _schedulePublish();
  }

  /// 屏蔽某一个发布者的全部推荐，只影响本机显示。
  Future<void> blockPublisher(String pubkey) async {
    if (pubkey.isEmpty || !_blocked.add(pubkey)) return;
    await _store.setBlocked(_profile, _blocked);
    _rebuild();
    notifyListeners();
  }

  Future<void> restoreBlocked() async {
    if (_blocked.isEmpty) return;
    _blocked = {};
    await _store.setBlocked(_profile, _blocked);
    _store.setSeeded(_profile, true);
    _rebuild();
    notifyListeners();
  }

  bool blockedPublisher(String pubkey) => _blocked.contains(pubkey);
  String get publicKey => _identity?.publicKey ?? '';

  Future<void> hidePublisher(String pubkey) => blockPublisher(pubkey);

  /// 不看这条：只影响本机显示，不改变发布内容。
  Future<void> hide(String dramaId) async {
    if (!_hidden.add(dramaId)) return;
    await _store.setHidden(_profile, _hidden);
    _rebuild();
    notifyListeners();
  }

  Future<void> restoreHidden() async {
    if (_hidden.isEmpty) return;
    _hidden = {};
    await _store.setHidden(_profile, _hidden);
    _rebuild();
    notifyListeners();
  }

  int get hiddenCount => _hidden.length;
  int get blockedCount => _blocked.length;

  void _markWatchDirty() {
    _watchDirty = true;
    if (_watchTimer != null) return;
    _watchTimer = Timer(watchSaveDelay, () {
      _watchTimer = null;
      if (_watchDirty) unawaited(_saveWatch());
    });
  }

  Future<void> _saveWatch() async {
    if (!_attached) return;
    _watchDirty = false;
    await _store.setWatch(_profile, _watch);
  }

  void _schedulePublish({bool immediate = false}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    _publishTimer?.cancel();
    if (immediate) {
      unawaited(_publish());
      return;
    }
    _publishTimer = Timer(publishDelay, () => unawaited(_publish()));
  }

  Future<void> _publish() async {
    final identity = _identity;
    final pool = _pool;
    final profile = _profile;
    if (!_attached || identity == null || pool == null || _publishing) return;
    _publishing = true;
    notifyListeners();
    try {
      final createdAt = max(_nowSeconds(), _publishedAt + 1);
      _publishedAt = createdAt;
      final event = NostrIdentity.sign(
        kind: recommendationKind,
        createdAt: createdAt,
        tags: [
          ['d', recommendationDTag],
          ['t', recommendationEventTag],
          ['client', recommendationClient],
        ],
        content: encodeVectorContent(_mine),
        secretHex: identity.secretHex,
      );
      _vectors[identity.publicKey] = RecommendationVector(
        pubkey: identity.publicKey,
        createdAt: createdAt,
        items: List.of(_mine),
      );
      await _store.setPublishedAt(profile, createdAt);
      if (!_attached || profile != _profile) return;
      _rebuild();
      final accepted = await pool.publish(event);
      if (!_attached || profile != _profile) return;
      _pendingPublish = accepted == 0;
      await _store.setPending(profile, _pendingPublish);
      _notice = _pendingPublish ? 'relay 未连接，推荐已保存在本机，联网后自动补发' : '';
      if (_pendingPublish) {
        _retryTimer?.cancel();
        _retryTimer = Timer(publishRetryDelay, () => unawaited(_publish()));
      }
    } catch (_) {
      _pendingPublish = true;
      _notice = '推荐暂时没有发出去，稍后会自动重试';
      _retryTimer?.cancel();
      _retryTimer = Timer(publishRetryDelay, () => unawaited(_publish()));
    } finally {
      _publishing = false;
      notifyListeners();
    }
  }

  void _onEvent(NostrEvent event) {
    final vector = decodeVectorEvent(event);
    if (vector == null) return;
    final existing = _vectors[vector.pubkey];
    if (existing != null && vector.createdAt <= existing.createdAt) return;
    if (_vectors.length >= maxVectors && existing == null) return;
    _vectors[vector.pubkey] = vector;
    final identity = _identity;
    if (identity != null &&
        vector.pubkey == identity.publicKey &&
        vector.createdAt >= _publishedAt) {
      _mine = List.of(vector.items);
      _publishedAt = vector.createdAt;
      unawaited(_store.setItems(_profile, _mine));
      unawaited(_store.setPublishedAt(_profile, vector.createdAt));
    }
    _scheduleRebuild();
  }

  void _onStatus() {
    if (_pendingPublish && (_pool?.connected ?? 0) > 0) {
      _schedulePublish();
    }
    notifyListeners();
  }

  void _onNotice(String message) {
    _notice = message;
    notifyListeners();
  }

  void _scheduleRebuild() {
    if (_rebuildTimer != null) return;
    _rebuildTimer = Timer(rebuildDelay, () {
      _rebuildTimer = null;
      _rebuild();
      notifyListeners();
    });
  }

  void _rebuild() {
    final vectors = _blocked.isEmpty
        ? _vectors.values.toList()
        : [
            for (final vector in _vectors.values)
              if (!_blocked.contains(vector.pubkey)) vector,
          ];
    final identity = _identity;
    if (identity != null) {
      vectors.removeWhere((vector) => vector.pubkey == identity.publicKey);
      vectors.add(
        RecommendationVector(
          pubkey: identity.publicKey,
          createdAt: _publishedAt,
          items: _mine,
        ),
      );
    }
    _feed = buildFeed(
      vectors,
      minePubkey: identity?.publicKey ?? '',
      hidden: _hidden,
    );
    _applyFilters();
  }

  void _applyFilters() {
    final local = _local;
    final scoped = _feed.where((item) {
      if (local != null && !local.allowsSource(item.source)) return false;
      if (_sources.isEmpty) return true;
      return _sources.contains(item.groupId);
    }).toList();
    final counts = <String, int>{};
    for (final item in scoped) {
      final name = _categoryOf(item);
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        if (a.value != b.value) return b.value.compareTo(a.value);
        return a.key.compareTo(b.key);
      });
    _categoryChoices = [
      for (final row in sorted.take(12)) CatalogCategory(row.key, row.key),
    ];
    if (_categoryFilter.isNotEmpty && !counts.containsKey(_categoryFilter)) {
      _categoryFilter = '';
    }
    _visible = _categoryFilter.isEmpty
        ? scoped
        : [
            for (final item in scoped)
              if (_categoryOf(item) == _categoryFilter) item,
          ];
  }

  String _categoryOf(FeedItem item) =>
      item.category.trim().isEmpty ? '' : categoryName(item.category);

  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

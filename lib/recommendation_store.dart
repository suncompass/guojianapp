import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recommendation_models.dart';
import 'secret_store.dart';

/// 一部剧在本机的观看累计，用于判断「看过了」是否可以自动进入动态。
class RecommendationWatch {
  RecommendationWatch({
    required this.entry,
    this.watchedMs = 0,
    Set<int>? episodes,
    this.published = false,
    this.lastEpisode,
    this.lastPosition,
    this.updatedAt = 0,
  }) : episodes = episodes ?? <int>{};

  RecommendationEntry entry;
  int watchedMs;
  final Set<int> episodes;
  bool published;
  int? lastEpisode;
  double? lastPosition;
  int updatedAt;

  /// 用户删除自己的推荐后重新计时，只有再次达到有效观看才会重新发布。
  void resetWatch() {
    watchedMs = 0;
    episodes.clear();
    published = false;
    lastEpisode = null;
    lastPosition = null;
  }

  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'ms': watchedMs,
    'episodes': episodes.toList()..sort(),
    'published': published,
    'lastEpisode': lastEpisode,
    'lastPosition': lastPosition,
    'updatedAt': updatedAt,
  };

  static RecommendationWatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final entry = raw['entry'] is Map
        ? RecommendationEntry.fromJson(
            Map<String, dynamic>.from(raw['entry'] as Map),
          )
        : null;
    if (entry == null ||
        !entry.cover.startsWith('http') ||
        entry.title.isEmpty) {
      return null;
    }
    return RecommendationWatch(
      entry: entry,
      watchedMs: raw['ms'] is num ? (raw['ms'] as num).toInt() : 0,
      episodes: {
        for (final value in raw['episodes'] as List? ?? [])
          if (value is num) value.toInt(),
      },
      published: raw['published'] == true,
      lastEpisode: raw['lastEpisode'] is num
          ? (raw['lastEpisode'] as num).toInt()
          : null,
      lastPosition: raw['lastPosition'] is num
          ? (raw['lastPosition'] as num).toDouble()
          : null,
      updatedAt: raw['updatedAt'] is num
          ? (raw['updatedAt'] as num).toInt()
          : 0,
    );
  }
}

/// 动态的本机记录按用户隔离保存，与剧库快照分开，避免影响备份与设备互联格式。
class RecommendationStore {
  RecommendationStore(this.preferences);

  final SharedPreferences preferences;

  static const prefix = 'recommend.v1';
  static const identities = 'identity';
  static const itemKey = 'items';
  static const watchKey = 'watch';
  static const publishedKey = 'publishedAt';
  static const pendingKey = 'pending';
  static const hiddenKey = 'hidden';
  static const blockedKey = 'blocked';
  static const seedKey = 'seed';
  static const filterKey = 'filter';

  String _key(String profile, String name) => '$prefix.$profile.$name';

  static bool _validSecret(String? value) =>
      value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  /// 明文记录优先：它只在密文能被跨进程解出同一内容后才会被清除，
  /// 因此两者同时存在时以它为准，避免把身份换成解不开的版本。
  String? identity(String profile) {
    final key = _key(profile, identities);
    final legacy = preferences.getString(key);
    if (_validSecret(legacy)) return legacy;
    final secure = SecretStore.cached(key);
    return _validSecret(secure) ? secure : null;
  }

  /// 本机是否已有身份记录（明文或密文），用于避免解密失败时误建新身份。
  bool hasStoredIdentity(String profile) {
    final key = _key(profile, identities);
    return preferences.getString(key) != null ||
        preferences.getString('$key${SecretStore.suffix}') != null;
  }

  /// 写入身份：尽力落到系统安全存储，同时保留明文到下一次启动复核。
  Future<void> setIdentity(String profile, String secret) async {
    final key = _key(profile, identities);
    await SecretStore.write(preferences, key, secret);
    await preferences.setString(key, secret);
  }

  /// 迁移已有的明文身份，并在确认密文可跨进程解出同一内容后清除明文。
  Future<void> upgradeIdentity(String profile) async {
    final key = _key(profile, identities);
    final legacy = preferences.getString(key);
    if (!_validSecret(legacy)) return;
    if (SecretStore.cached(key) == legacy) {
      await preferences.remove(key);
      return;
    }
    // 已有密文却解不开时保留明文，也不再反复重写，等平台恢复后由下次启动复核。
    if (preferences.getString('$key${SecretStore.suffix}') == null) {
      await SecretStore.write(preferences, key, legacy!);
    }
  }

  List<RecommendationEntry> items(String profile) {
    final raw = preferences.getString(_key(profile, itemKey));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = <RecommendationEntry>[];
      final seen = <String>{};
      for (final row in decoded) {
        if (row is! Map) continue;
        final item = RecommendationEntry.fromJson(
          Map<String, dynamic>.from(row),
        );
        final valid = RecommendationEntry.fromFields(
          source: item.source,
          id: item.id,
          title: item.title,
          cover: item.cover,
          category: item.category,
          at: item.at,
        );
        if (valid == null || !seen.add(valid.id)) continue;
        items.add(valid);
        if (items.length >= recommendationItemLimit) break;
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> setItems(String profile, List<RecommendationEntry> items) =>
      preferences.setString(
        _key(profile, itemKey),
        jsonEncode([for (final item in items) item.toJson()]),
      );

  Map<String, RecommendationWatch> watch(String profile) {
    final raw = preferences.getString(_key(profile, watchKey));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, RecommendationWatch>{};
      decoded.forEach((key, value) {
        final entry = RecommendationWatch.fromJson(value);
        if (entry == null) return;
        result['$key'] = entry;
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> setWatch(
    String profile,
    Map<String, RecommendationWatch> watch,
  ) {
    final rows = watch.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    return preferences.setString(
      _key(profile, watchKey),
      jsonEncode({
        for (final row in rows.take(300)) row.key: row.value.toJson(),
      }),
    );
  }

  int publishedAt(String profile) =>
      preferences.getInt(_key(profile, publishedKey)) ?? 0;

  Future<void> setPublishedAt(String profile, int value) =>
      preferences.setInt(_key(profile, publishedKey), value);

  bool pending(String profile) =>
      preferences.getBool(_key(profile, pendingKey)) ?? false;

  Future<void> setPending(String profile, bool value) =>
      preferences.setBool(_key(profile, pendingKey), value);

  Set<String> hidden(String profile) {
    final raw = preferences.getStringList(_key(profile, hiddenKey));
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> setHidden(String profile, Set<String> ids) =>
      preferences.setStringList(_key(profile, hiddenKey), ids.toList());

  Set<String> blocked(String profile) {
    final raw = preferences.getStringList(_key(profile, blockedKey));
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> setBlocked(String profile, Set<String> pubkeys) =>
      preferences.setStringList(_key(profile, blockedKey), pubkeys.toList());

  bool seeded(String profile) =>
      preferences.getBool(_key(profile, seedKey)) ?? false;

  Future<void> setSeeded(String profile, bool value) =>
      preferences.setBool(_key(profile, seedKey), value);

  ({Set<String> sources, String category, bool chosen}) filter(String profile) {
    final empty = (sources: <String>{}, category: '', chosen: false);
    final raw = preferences.getString(_key(profile, filterKey));
    if (raw == null) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return empty;
      final category = '${decoded['category'] ?? ''}';
      final sources = decoded['sources'];
      if (sources is List) {
        return (
          sources: {
            for (final entry in sources)
              if ('$entry'.isNotEmpty) '$entry',
          },
          category: category,
          chosen: true,
        );
      }
      final legacy = '${decoded['source'] ?? ''}';
      return (
        sources: legacy.isEmpty || legacy == 'all' ? <String>{} : {legacy},
        category: category,
        chosen: true,
      );
    } catch (_) {
      return empty;
    }
  }

  Future<void> setFilter(
    String profile, {
    required Set<String> sources,
    required String category,
  }) => preferences.setString(
    _key(profile, filterKey),
    jsonEncode({'sources': sources.toList(), 'category': category}),
  );

  /// 删除不存在的用户留下的动态记录。
  Future<void> pruneProfiles(Set<String> profiles) async {
    final stale = <String>[];
    for (final key in preferences.getKeys()) {
      if (!key.startsWith('$prefix.')) continue;
      final rest = key.substring(prefix.length + 1);
      final separator = rest.indexOf('.');
      if (separator <= 0) continue;
      if (!profiles.contains(rest.substring(0, separator))) stale.add(key);
    }
    for (final key in stale) {
      await preferences.remove(key);
    }
  }
}

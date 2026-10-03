import 'dart:convert';

import 'models.dart';
import 'nostr_crypto.dart';

/// 动态使用独立的 nostr 榜单：kind 30078 的可替换事件，每个用户维护一份自己的推荐列表。
///
/// 与 `../nostr` 的投票榜共用事件格式思路，但 `d` 标签不同，两边人数不合并。
const int recommendationKind = 30078;
const String recommendationDTag = 'zhenguo:app:recommend:v1';
const String recommendationEventTag = 'zhenguo-app-recommend';
const String recommendationClient = 'zhenguojian-app';
const int recommendationVersion = 1;
const int recommendationItemLimit = 200;

/// 动态里的一条推荐记录。字段取海报墙需要的最小集合：站源、剧集 ID、剧名、海报、分类、时间。
class RecommendationEntry {
  const RecommendationEntry({
    required this.source,
    required this.id,
    required this.title,
    required this.cover,
    this.category = '',
    required this.at,
  });

  final String source;
  final String id;
  final String title;
  final String cover;
  final String category;
  final int at;

  static const titleLimit = 80;
  static const coverLimit = 400;
  static const categoryLimit = 24;
  static const idLimit = 120;

  factory RecommendationEntry.fromDrama(Drama drama, {required int at}) =>
      RecommendationEntry(
        source: drama.source,
        id: drama.id,
        title: drama.title,
        cover: drama.cover,
        category: drama.category,
        at: at,
      );

  Drama get drama => Drama(
    id: id,
    source: source,
    title: title,
    cover: cover,
    category: category,
  );

  List<Object> toWire() => [source, id, title, cover, category, at];

  Map<String, dynamic> toJson() => {
    'source': source,
    'id': id,
    'title': title,
    'cover': cover,
    'category': category,
    'at': at,
  };

  factory RecommendationEntry.fromJson(Map<String, dynamic> json) =>
      RecommendationEntry(
        source: '${json['source']}',
        id: '${json['id']}',
        title: '${json['title']}',
        cover: '${json['cover'] ?? ''}',
        category: '${json['category'] ?? ''}',
        at: json['at'] is num ? (json['at'] as num).toInt() : 0,
      );

  static RecommendationEntry? fromWire(Object? raw) {
    if (raw is! List || raw.length < 4) return null;
    var category = '';
    var at = 0;
    if (raw.length >= 6) {
      category = '${raw[4]}';
      at = raw[5] is num ? (raw[5] as num).toInt() : 0;
    } else if (raw.length == 5) {
      if (raw[4] is num) {
        at = (raw[4] as num).toInt();
      } else {
        category = '${raw[4]}';
      }
    }
    return fromFields(
      source: '${raw[0]}',
      id: '${raw[1]}',
      title: '${raw[2]}',
      cover: '${raw[3]}',
      category: category,
      at: at,
    );
  }

  /// 只接受本应用认识的站源、非空剧名和可下载海报，避免脏数据进入榜单。
  static RecommendationEntry? fromFields({
    required String source,
    required String id,
    required String title,
    required String cover,
    required String category,
    required int at,
  }) {
    final site = source.trim();
    final dramaId = id.trim();
    final name = title.trim();
    final poster = cover.trim();
    if (!SourceSite.isKnown(site)) return null;
    if (dramaId.isEmpty || dramaId.length > idLimit) return null;
    if (name.isEmpty) return null;
    if (!poster.startsWith('https://') && !poster.startsWith('http://')) {
      return null;
    }
    return RecommendationEntry(
      source: site,
      id: dramaId,
      title: name.length > titleLimit ? name.substring(0, titleLimit) : name,
      cover: poster.length > coverLimit
          ? poster.substring(0, coverLimit)
          : poster,
      category: category.trim().length > categoryLimit
          ? category.trim().substring(0, categoryLimit)
          : category.trim(),
      at: at < 0 ? 0 : at,
    );
  }
}

/// 一个用户在 relay 上的完整推荐列表。
class RecommendationVector {
  const RecommendationVector({
    required this.pubkey,
    required this.createdAt,
    required this.items,
  });

  final String pubkey;
  final int createdAt;
  final List<RecommendationEntry> items;
}

/// 榜单聚合后的一条：同一部剧按推荐人数合并。
class FeedItem {
  const FeedItem({
    required this.source,
    required this.id,
    required this.title,
    required this.cover,
    required this.category,
    required this.recommenders,
    required this.latest,
    required this.mine,
    this.publishers = const {},
  });

  final String source;
  final String id;
  final String title;
  final String cover;
  final String category;
  final int recommenders;
  final int latest;
  final bool mine;
  final Set<String> publishers;

  Drama get drama => Drama(
    id: id,
    source: source,
    title: title,
    cover: cover,
    category: category,
  );

  String get groupId => SourceSite.byId(source).groupId;
  String get sourceName => SourceSite.byId(source).name;
  String get groupName => SourceSite.byId(source).groupName;
  String get recommendLabel => '$recommenders 人';
}

String encodeVectorContent(Iterable<RecommendationEntry> items) => jsonEncode({
  'v': recommendationVersion,
  'i': [for (final item in items) item.toWire()],
});

/// 解析 relay 上的推荐事件；空列表是合法内容（用户删除了自己的全部推荐）。
RecommendationVector? decodeVectorEvent(NostrEvent event) {
  if (event.kind != recommendationKind) return null;
  if (event.pubkey.length != 64 || event.id.isEmpty) return null;
  if (event.tagValue('d') != recommendationDTag) return null;
  final Object? content;
  try {
    content = jsonDecode(event.content);
  } catch (_) {
    return null;
  }
  if (content is! Map) return null;
  if (content['v'] is! num ||
      (content['v'] as num).toInt() != recommendationVersion) {
    return null;
  }
  final raw = content['i'];
  if (raw is! List) return null;
  final items = <RecommendationEntry>[];
  final seen = <String>{};
  for (final row in raw) {
    final item = RecommendationEntry.fromWire(row);
    if (item == null || !seen.add(item.id)) continue;
    items.add(item);
    if (items.length >= recommendationItemLimit) break;
  }
  return RecommendationVector(
    pubkey: event.pubkey,
    createdAt: event.createdAt,
    items: items,
  );
}

/// 合并所有用户的推荐列表，按推荐人数从多到少排序。
List<FeedItem> buildFeed(
  Iterable<RecommendationVector> vectors, {
  String minePubkey = '',
  Set<String> hidden = const {},
}) {
  final entries = <String, RecommendationEntry>{};
  final latest = <String, int>{};
  final owners = <String, Set<String>>{};
  for (final vector in vectors) {
    for (final item in vector.items) {
      if (item.id.isEmpty) continue;
      latest[item.id] = item.at > (latest[item.id] ?? 0)
          ? item.at
          : latest[item.id] ?? 0;
      final previous = entries[item.id];
      if (previous == null ||
          (previous.cover.isEmpty && item.cover.isNotEmpty)) {
        entries[item.id] = item;
      }
      (owners[item.id] ??= <String>{}).add(vector.pubkey);
    }
  }
  final items = <FeedItem>[];
  entries.forEach((id, entry) {
    if (hidden.contains(id)) return;
    final people = owners[id]?.length ?? 0;
    if (people <= 0) return;
    items.add(
      FeedItem(
        source: entry.source,
        id: entry.id,
        title: entry.title,
        cover: entry.cover,
        category: entry.category,
        recommenders: people,
        latest: latest[id] ?? 0,
        mine:
            minePubkey.isNotEmpty &&
            (owners[id]?.contains(minePubkey) ?? false),
        publishers: owners[id] ?? const {},
      ),
    );
  });
  items.sort((a, b) {
    if (a.recommenders != b.recommenders) {
      return b.recommenders.compareTo(a.recommenders);
    }
    if (a.latest != b.latest) return b.latest.compareTo(a.latest);
    return a.title.compareTo(b.title);
  });
  return items;
}

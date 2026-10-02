import 'models.dart';

class RankingBoard {
  const RankingBoard({
    required this.id,
    required this.source,
    required this.name,
    this.description = '',
  });
  final String id;
  final String source;
  final String name;
  final String description;
  String get groupId => SourceSite.byId(source).groupId;

  /// 榜单 ID 一律是「站源前缀-榜单名」，前缀就是站源。
  ///
  /// 之前这里写死了六个站源的 ID 清单，其余一律返回空串；原生核心新增的
  /// 短剧站源榜单（芽果、猫果、饭果、观果、河果、星果、花果、牛果、皮果、伍果）
  /// 因此全部解析不到站源，`CoreRepository` 授权时当成「不属于任何站源」直接拒绝，
  /// 表现为这些榜单一条数据都没有。这里按前缀解析并归一化别名，新增榜单无需再改。
  static const sourceAliases = {'huangguo': 'huangguoai'};

  static String sourceForID(String id) {
    final prefix = id.split('-').first.trim().toLowerCase();
    final source = sourceAliases[prefix] ?? prefix;
    return SourceSite.isKnown(source) ? source : '';
  }

  factory RankingBoard.fromJson(Map<String, dynamic> json) => RankingBoard(
    id: json['id'] as String? ?? '',
    source:
        json['source'] as String? ?? sourceForID(json['id'] as String? ?? ''),
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );
}

class RankingItem {
  const RankingItem(this.rank, this.drama, {this.metric = ''});
  final int rank;
  final Drama drama;
  final String metric;
  factory RankingItem.fromJson(Map<String, dynamic> json) => RankingItem(
    intValue(json['rank']),
    Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    metric: json['metric'] as String? ?? '',
  );
}

class RankingPage {
  const RankingPage({
    required this.items,
    this.page = 1,
    this.hasMore = false,
    this.warning = '',
    this.updatedText = '',
    this.stale = false,
  });
  final List<RankingItem> items;
  final int page;
  final bool hasMore;
  final String warning;
  final String updatedText;
  final bool stale;
  factory RankingPage.fromJson(Map<String, dynamic> json) => RankingPage(
    items: [
      for (final row in json['items'] as List? ?? [])
        RankingItem.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    page: intValue(json['page']),
    hasMore: json['hasMore'] == true,
    warning: json['warning'] as String? ?? '',
    updatedText: json['updatedText'] as String? ?? '',
    stale: json['stale'] == true,
  );
}

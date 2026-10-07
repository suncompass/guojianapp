import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原生核心 `provider_rankings.go` 里属于绿色站源的榜单（ID → 站源）。
const nativeBoardSources = <String, String>{
  'hongguo-hot': 'hongguo',
  'hongguo-real': 'hongguo',
  'hongguo-comic': 'hongguo',
  'hongguo-ai': 'hongguo',
  'yaguo-rank': 'yaguo',
  'yaguo-theater': 'yaguo',
  'maoguo-recommend': 'maoguo',
  'fanguo-urban': 'fanguo',
  'fanguo-sweet': 'fanguo',
  'fanguo-counter': 'fanguo',
  'guanguo-catalog': 'guanguo',
  'heguo-sweet': 'heguo',
  'heguo-xianxia': 'heguo',
  'heguo-romance': 'heguo',
  'xingguo-recommend': 'xingguo',
  'huaguo-drama': 'huaguo',
  'niuguo-drama': 'niuguo',
  'niuguo-movie': 'niuguo',
  'niuguo-tv': 'niuguo',
  'niuguo-anime': 'niuguo',
  'niuguo-variety': 'niuguo',
  'wuguo-urban': 'wuguo',
  'wuguo-counter': 'wuguo',
  'wuguo-travel': 'wuguo',
  'wuguo-female': 'wuguo',
  'wuguo-male': 'wuguo',
  'miguo-short': 'miguo',
  'miguo-series': 'miguo',
  'miguo-movie': 'miguo',
  'miguo-anime': 'miguo',
  'miguo-variety': 'miguo',
  'miguo-netflix': 'miguo',
  'shuangguo-all': 'shuangguo',
  'shuangguo-reversal': 'shuangguo',
  'shuangguo-costume': 'shuangguo',
  'shuangguo-female': 'shuangguo',
  'shuangguo-era': 'shuangguo',
  'shuangguo-romance': 'shuangguo',
  'shuangguo-urban': 'shuangguo',
  'shuangguo-short': 'shuangguo',
};

/// 成人站源、已下线站源与黄果家族的榜单 ID：即便还能解析出站源，也必须不可用，
/// 否则会向原生核心发起一个它不再放行的请求（原生核心的榜单列表同样按白名单过滤）。
const retiredBoardIds = <String>[
  'huangdou-all',
  'huangdou-mogai',
  'huangdou-search',
  'huangdou-favorite',
  'huangdou-finish',
  'huangguo-hot',
  'huangguo-recommend',
  'huangguo-potential',
  'huangju-hot',
  'huangju-new',
  'yeguo-recommend',
  'dsd-catalog',
  'chaoguo-hot',
  'chaoguo-mainstream',
  'chaoguo-adult',
  'chaoguo-anime',
  'chaoguo-urban',
  'chaoguo-counter',
  'chaoguo-costume',
  'chaoguo-travel',
];

void main() {
  test('every green native ranking board resolves to its own source', () {
    final wrong = <String>[];
    for (final entry in nativeBoardSources.entries) {
      final resolved = RankingBoard.sourceForID(entry.key);
      if (resolved != entry.value) {
        wrong.add('${entry.key} 解析为 "$resolved"，应为 "${entry.value}"');
      }
    }
    expect(wrong, isEmpty);
  });

  test('board sources are known so 授权不会误判为未知站源', () {
    for (final source in nativeBoardSources.values) {
      expect(
        SourceSite.isKnown(source),
        isTrue,
        reason: '$source 未登记在 SourceSite 中',
      );
      expect(SourceSite.isAvailable(source), isTrue, reason: '$source 不在可用站源里');
    }
  });

  test('retired ranking boards never resolve to an available source', () {
    for (final id in retiredBoardIds) {
      final source = RankingBoard.sourceForID(id);
      expect(
        SourceSite.isAvailable(source),
        isFalse,
        reason: '$id 仍解析出可用站源 "$source"',
      );
    }
  });

  test('unknown board ids resolve to an empty source instead of a guess', () {
    expect(RankingBoard.sourceForID(''), isEmpty);
    expect(RankingBoard.sourceForID('unknown-board'), isEmpty);
  });

  test('boards keep the source reported by the native core', () {
    final board = RankingBoard.fromJson(const {
      'id': 'hongguo-hot',
      'source': 'hongguo',
      'name': '总热播榜',
    });
    expect(board.source, 'hongguo');
    expect(board.groupId, 'hongguo');
  });
}

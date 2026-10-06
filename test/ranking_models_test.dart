import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原生核心 `provider_rankings.go` 现在只提供红果榜单。
const nativeBoardSources = <String, String>{
  'hongguo-hot': 'hongguo',
  'hongguo-real': 'hongguo',
  'hongguo-comic': 'hongguo',
  'hongguo-ai': 'hongguo',
};

/// 随第三方站源一起下线的榜单 ID：即便还能解析出站源，也必须不可用，
/// 否则会向原生核心发起一个它不再提供的请求。
const retiredBoardIds = <String>[
  'huangdou-all',
  'huangguo-hot',
  'huangju-hot',
  'yeguo-recommend',
  'dsd-catalog',
  'yaguo-rank',
  'maoguo-recommend',
  'fanguo-urban',
  'guanguo-catalog',
  'heguo-sweet',
  'xingguo-recommend',
  'huaguo-drama',
  'niuguo-drama',
  'piguo-hit',
  'wuguo-urban',
  'chaoguo-hot',
];

void main() {
  test('every remaining native ranking board resolves to hongguo', () {
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
      expect(
        SourceSite.isAvailable(source),
        isTrue,
        reason: '$source 不在可用站源里',
      );
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

import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原生核心 `provider_rankings.go` 的完整榜单表：榜单 ID → 站源。
///
/// 这份清单与 Go 侧一一对应，用来防止再次出现「Dart 只认识一部分榜单」的问题。
const nativeBoardSources = <String, String>{
  'hongguo-hot': 'hongguo',
  'hongguo-real': 'hongguo',
  'hongguo-comic': 'hongguo',
  'hongguo-ai': 'hongguo',
  'huangdou-all': 'huangdou',
  'huangdou-mogai': 'huangdou',
  'huangdou-search': 'huangdou',
  'huangdou-favorite': 'huangdou',
  'huangdou-finish': 'huangdou',
  'huangguo-hot': 'huangguoai',
  'huangguo-recommend': 'huangguoai',
  'huangguo-potential': 'huangguoai',
  'huangju-hot': 'huangju',
  'huangju-new': 'huangju',
  'yeguo-recommend': 'yeguo',
  'dsd-catalog': 'dsd',
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
  'piguo-hit': 'piguo',
  'piguo-romance': 'piguo',
  'piguo-costume': 'piguo',
  'wuguo-urban': 'wuguo',
  'wuguo-counter': 'wuguo',
  'wuguo-travel': 'wuguo',
  'wuguo-female': 'wuguo',
  'wuguo-male': 'wuguo',
};

void main() {
  test('every native ranking board resolves to its real source', () {
    final wrong = <String>[];
    for (final entry in nativeBoardSources.entries) {
      final resolved = RankingBoard.sourceForID(entry.key);
      if (resolved != entry.value) {
        wrong.add('${entry.key} 解析为 "$resolved"，应为 "${entry.value}"');
      }
    }
    expect(wrong, isEmpty);
  });

  test('board sources are known so授权不会误判为未知站源', () {
    for (final source in nativeBoardSources.values) {
      expect(
        SourceSite.isKnown(source),
        isTrue,
        reason: '$source 未登记在 SourceSite.allValues 中',
      );
    }
  });

  test('授权用的站源在全站源版本里都是可用站源', () {
    for (final entry in nativeBoardSources.entries) {
      final source = RankingBoard.sourceForID(entry.key);
      expect(
        SourceSite.isKnown(source),
        isTrue,
        reason: '${entry.key} 解析出的站源 "$source" 会导致榜单被拒绝',
      );
      if (allSourcesEnabled) {
        expect(
          SourceSite.isAvailable(source),
          isTrue,
          reason: '${entry.key} 解析出的站源 "$source" 不在可用站源里',
        );
      }
    }
  });

  test('unknown board ids resolve to an empty source instead of a guess', () {
    expect(RankingBoard.sourceForID(''), isEmpty);
    expect(RankingBoard.sourceForID('unknown-board'), isEmpty);
  });

  test('boards keep the source reported by the native core', () {
    final board = RankingBoard.fromJson(const {
      'id': 'maoguo-recommend',
      'source': 'maoguo',
      'name': '推荐榜',
    });
    expect(board.source, 'maoguo');
    expect(board.groupId, 'maoguo');
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:duanju_app/nostr_crypto.dart';
import 'package:duanju_app/recommendation_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret =
    '0000000000000000000000000000000000000000000000000000000000000003';
const _otherSecret =
    'b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef';

NostrEvent _event({
  required String content,
  required String secret,
  int createdAt = 1760000000,
  String dTag = recommendationDTag,
  int kind = recommendationKind,
}) => NostrIdentity.sign(
  kind: kind,
  createdAt: createdAt,
  tags: [
    ['d', dTag],
    ['t', recommendationEventTag],
  ],
  content: content,
  secretHex: secret,
  aux: Uint8List(32),
);

String _vector(List<List<Object>> items) =>
    jsonEncode({'v': recommendationVersion, 'i': items});

void main() {
  group('推荐记录', () {
    test('合法记录往返', () {
      final entry = RecommendationEntry.fromWire([
        'hongguo',
        'hongguo:1',
        '都市逆袭',
        'https://img.example.com/a.jpg',
        '都市',
        1760000000,
      ]);
      expect(entry, isNotNull);
      expect(entry!.source, 'hongguo');
      expect(entry.id, 'hongguo:1');
      expect(entry.category, '都市');
      expect(entry.at, 1760000000);
      expect(entry.toWire(), [
        'hongguo',
        'hongguo:1',
        '都市逆袭',
        'https://img.example.com/a.jpg',
        '都市',
        1760000000,
      ]);
      expect(
        RecommendationEntry.fromJson(entry.toJson()).toWire(),
        entry.toWire(),
      );
    });

    test('兼容不带分类的五字段写法', () {
      final entry = RecommendationEntry.fromWire([
        'hongguo',
        'hongguo:2',
        '剧名',
        'https://img.example.com/b.jpg',
        1760000001,
      ]);
      expect(entry, isNotNull);
      expect(entry!.category, '');
      expect(entry.at, 1760000001);
    });

    test('未知站源、空剧名、无海报都会被拒绝', () {
      expect(
        RecommendationEntry.fromWire([
          'weizhi',
          'weizhi:1',
          '剧名',
          'https://img.example.com/a.jpg',
          '都市',
          1,
        ]),
        isNull,
      );
      expect(
        RecommendationEntry.fromWire([
          'hongguo',
          'hongguo:1',
          '   ',
          'https://img.example.com/a.jpg',
          '都市',
          1,
        ]),
        isNull,
      );
      expect(
        RecommendationEntry.fromWire(['hongguo', 'hongguo:1', '剧名', '', '都市', 1]),
        isNull,
      );
      expect(RecommendationEntry.fromWire(['hongguo', 'hongguo:1']), isNull);
    });

    test('超长字段被截断而不是丢弃', () {
      final entry = RecommendationEntry.fromWire([
        'hongguo',
        'hongguo:3',
        '剧' * 200,
        'https://img.example.com/${'a' * 600}.jpg',
        '分' * 40,
        1,
      ]);
      expect(entry, isNotNull);
      expect(entry!.title.length, RecommendationEntry.titleLimit);
      expect(entry.cover.length, RecommendationEntry.coverLimit);
      expect(entry.category.length, RecommendationEntry.categoryLimit);
    });
  });

  group('事件解析', () {
    test('解析自己的推荐列表', () {
      final event = _event(
        secret: _secret,
        content: _vector([
          [
            'hongguo',
            'hongguo:1',
            '都市逆袭',
            'https://img.example.com/a.jpg',
            '都市',
            1760000000,
          ],
          [
            'yaguo',
            'yaguo:9',
            '古装剧',
            'https://img.example.com/b.jpg',
            '古装',
            1760000001,
          ],
        ]),
      );
      final vector = decodeVectorEvent(event);
      expect(vector, isNotNull);
      expect(vector!.pubkey, event.pubkey);
      expect(vector.items.length, 2);
      expect(vector.items.first.title, '都市逆袭');
    });

    test('空列表是合法内容，用于撤销自己的推荐', () {
      final vector = decodeVectorEvent(
        _event(secret: _secret, content: _vector([])),
      );
      expect(vector, isNotNull);
      expect(vector!.items, isEmpty);
    });

    test('同一条记录重复出现只算一次', () {
      final vector = decodeVectorEvent(
        _event(
          secret: _secret,
          content: _vector([
            ['hongguo', 'hongguo:1', '剧名', 'https://i.example.com/a.jpg', '', 1],
            ['hongguo', 'hongguo:1', '剧名', 'https://i.example.com/a.jpg', '', 2],
          ]),
        ),
      );
      expect(vector!.items.length, 1);
    });

    test('d 标签、kind、版本不匹配时忽略事件', () {
      expect(
        decodeVectorEvent(
          _event(
            secret: _secret,
            content: _vector([]),
            dTag: 'zhenguo:duanju:vote:v2',
          ),
        ),
        isNull,
      );
      expect(
        decodeVectorEvent(
          _event(secret: _secret, content: _vector([]), kind: 1),
        ),
        isNull,
      );
      expect(
        decodeVectorEvent(
          _event(
            secret: _secret,
            content: jsonEncode({'v': 99, 'i': <Object>[]}),
          ),
        ),
        isNull,
      );
      expect(
        decodeVectorEvent(
          _event(secret: _secret, content: jsonEncode({'v': 1, 'i': 'x'})),
        ),
        isNull,
      );
      expect(
        decodeVectorEvent(_event(secret: _secret, content: '不是 JSON')),
        isNull,
      );
    });

    test('事件内容里的脏记录被逐条丢弃', () {
      final vector = decodeVectorEvent(
        _event(
          secret: _secret,
          content: _vector([
            ['weizhi', 'weizhi:1', '剧名', 'https://i.example.com/a.jpg', '', 1],
            ['hongguo', 'hongguo:1', '', 'https://i.example.com/a.jpg', '', 1],
            ['hongguo', 'hongguo:2', '好剧', 'https://i.example.com/b.jpg', '', 2],
          ]),
        ),
      );
      expect(vector!.items.length, 1);
      expect(vector.items.single.id, 'hongguo:2');
    });
  });

  group('榜单聚合', () {
    test('按推荐人数排序，同一部剧合并', () {
      final mine = _event(
        secret: _secret,
        content: _vector([
          ['hongguo', 'hongguo:1', '被两个人推荐', 'https://i.example.com/a.jpg', '', 100],
          ['hongguo', 'hongguo:2', '只有我推荐', 'https://i.example.com/b.jpg', '', 200],
        ]),
      );
      final other = _event(
        secret: _otherSecret,
        content: _vector([
          ['hongguo', 'hongguo:1', '被两个人推荐', 'https://i.example.com/a.jpg', '', 300],
        ]),
        createdAt: 1760000100,
      );
      final vectors = [decodeVectorEvent(mine)!, decodeVectorEvent(other)!];
      final feed = buildFeed(vectors, minePubkey: mine.pubkey);
      expect(feed.length, 2);
      expect(feed.first.id, 'hongguo:1');
      expect(feed.first.recommenders, 2);
      expect(feed.first.latest, 300);
      expect(feed.first.mine, isTrue);
      expect(feed.last.id, 'hongguo:2');
      expect(feed.last.recommenders, 1);
      expect(feed.last.recommendLabel, '1 人');
    });

    test('同一个人重复出现只算一个人', () {
      final first = _event(
        secret: _secret,
        content: _vector([
          ['hongguo', 'hongguo:1', '剧名', 'https://i.example.com/a.jpg', '', 100],
        ]),
      );
      final second = _event(
        secret: _secret,
        content: _vector([
          ['hongguo', 'hongguo:1', '剧名', 'https://i.example.com/a.jpg', '', 200],
        ]),
        createdAt: 1760000200,
      );
      final feed = buildFeed([
        decodeVectorEvent(first)!,
        decodeVectorEvent(second)!,
      ]);
      expect(feed.single.recommenders, 1, reason: '同一个公钥只算一个人');
      expect(feed.single.latest, 200);
    });

    test('隐藏的记录不会出现在榜单里', () {
      final event = _event(
        secret: _secret,
        content: _vector([
          ['hongguo', 'hongguo:1', '剧名', 'https://i.example.com/a.jpg', '', 100],
        ]),
      );
      expect(buildFeed([decodeVectorEvent(event)!]), hasLength(1));
      expect(
        buildFeed([decodeVectorEvent(event)!], hidden: {'hongguo:1'}),
        isEmpty,
      );
    });
  });
}

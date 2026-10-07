import 'dart:convert';

import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_profiles.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const red = FixtureRepository.free;
  const other = FixtureRepository.vip;

  test('retired third-party sources stay known but unavailable', () async {
    SharedPreferences.setMockInitialValues({'source': 'huangdou'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(appSlug, 'hongguojian');
    expect(
      store.sources.map((source) => source.id),
      SourceSite.values.map((source) => source.id),
    );
    expect(SourceSite.values.map((source) => source.id), contains('hongguo'));
    // 单版本只装绿色站源：红果 + 11 个绿色短剧站源。
    expect(SourceSite.values.length, 12);
    expect(SourceSite.isAvailable('miguo'), isTrue);
    expect(SourceSite.isAvailable('shuangguo'), isTrue);
    expect(SourceSite.isAvailable('huangdou'), isFalse);
    // 成人站源既不注册也不可用，但标识必须仍然认得。
    expect(SourceSite.isAvailable('yanguo'), isFalse);
    // 旧数据里出现过的站源必须仍然认得，否则升级后原有用户的站源权限会被判成无效。
    expect(SourceSite.isKnown('huangdou'), isTrue);
    expect(SourceSite.isKnown('chaoguo'), isTrue);
    expect(SourceSite.isKnown('yanguo'), isTrue);
    expect(SourceSite.isKnown('unknown'), isFalse);
    expect(SourceSite.byId('huangdou').id, 'hongguo');
    expect(store.allowsSource('huangdou'), isFalse);
    expect(store.source, 'hongguo');
    store.dispose();
  });

  test(
    'records from retired sources survive backup restore without becoming available',
    () async {
      final history = [
        for (final drama in [red, other])
          WatchEntry(
            drama: drama,
            episode: 1,
            position: 12,
            duration: 60,
            updatedAt: DateTime(2026, 9, 19),
          ).toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        'source': 'huangdou',
        'favorites': jsonEncode([red.toJson(), other.toJson()]),
        'history': jsonEncode(history),
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      // 停用站源的记录不再进入收藏与历史，但备份里原有的行不会被抹掉。
      expect(store.favorites.length, 1);
      expect(store.history.length, 1);
      expect(store.isFavorite(other.id), isFalse);
      expect(store.watched(other.id) != null, isFalse);
      await store.toggleFavorite(red);
      final backup = await store.exportBackup();
      final library =
          (jsonDecode(backup)['libraries'] as Map)['default'] as Map;
      expect((library['favorites'] as List).map((row) => (row as Map)['id']), [
        other.id,
      ]);
      expect(library['history'], hasLength(2));
      await store.importBackup(backup);
      expect(store.preferences.getString('source'), 'huangdou');
      expect(store.history, hasLength(1));
      expect(store.favorites.map((drama) => drama.id), isEmpty);
      store.dispose();
    },
  );

  test(
    'a restored retired-source profile keeps its identity and permissions',
    () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '已有用户',
            sources: ['huangdou'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'huangdou',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(store.configurationError, isNull);
      expect(store.profile.id, 'viewer');
      expect(store.profile.admin, isFalse);
      expect(store.profile.sources, ['huangdou']);
      expect(store.canDownload, isFalse);
      expect(store.source, '');
      expect(store.allowsSource('hongguo'), isFalse);
      expect(store.allowsSource('huangdou'), isFalse);
      store.dispose();
    },
  );

  test(
    'retired DSD profile data stays readable after the source is gone',
    () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '旧用户',
            sources: ['dsd'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'dsd',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(store.configurationError, isNull);
      expect(store.profile.sources, ['dsd']);
      expect(store.sources, isEmpty);
      expect(store.source, '');
      expect(store.allowsSource('dsd'), isFalse);
      store.dispose();
    },
  );

  test(
    'background requests reject unavailable sources before native I/O',
    () async {
      final repository = NativeRepository(background: true);
      final denied = [...SourceSite.retiredIds, 'unknown'];
      for (final source in denied) {
        final drama = Drama(id: '$source:123', source: source, title: '合成数据');
        final episode = Episode({'id': '1'}, 1);
        for (final request in [
          () => repository.catalog(source),
          () => repository.cached(source),
          () => repository.sourceStatus(source),
          () => repository.startSourceJob(source, 'update'),
          () => repository.cancelSourceJob(source),
          () => repository.detail(drama),
          () => repository.cover(drama),
          () => repository.resolve(drama, episode),
          () => repository.resolveOnline(drama, episode),
          () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [
            episode,
          ]),
          () => repository.localPlayback(drama, episode),
        ]) {
          await expectLater(
            request(),
            throwsA(
              isA<AppFailure>().having(
                (error) => error.message,
                'message',
                '当前版本不包含此站源',
              ),
            ),
          );
        }
      }
    },
  );
}

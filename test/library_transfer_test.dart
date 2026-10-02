import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duanju_app/core_bridge.dart';

import 'fixtures.dart';
import 'package:duanju_app/library_transfer.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/profiles_screen.dart';

void main() {
  test('library import and export stay available before unlocking', () {
    for (final action in const [
      'libraryExport',
      'libraryImport',
      'libraryExportXZ',
      'libraryImportXZ',
    ]) {
      expect(unlockedActions, contains(action), reason: '$action 不应要求先解锁当前用户');
    }
    expect(unlockedActions, isNot(contains('catalog')));
    expect(unlockedActions, isNot(contains('downloads')));
  });

  test('exported packages are named and detected as xz archives', () {
    expect(libraryPackageFileName(DateTime(2026, 10, 1)), '剧库-2026-10-01.xz');
    expect(
      libraryPackageIsXZ(
        Uint8List.fromList([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 0x00, 0x04]),
      ),
      isTrue,
    );
    expect(
      libraryPackageIsXZ(Uint8List.fromList(utf8.encode('{"kind":"library"}'))),
      isFalse,
    );
    expect(libraryPackageIsXZ(Uint8List.fromList(const [])), isFalse);
    expect(
      libraryPackageIsXZ(Uint8List.fromList(const [0xfd, 0x37, 0x7a])),
      isFalse,
    );
  });

  test('a legacy json package is still accepted while xz is the default', () {
    final document = parseLibraryPackage(
      jsonEncode({
        'app': 'guoguojuku',
        'kind': 'library',
        'version': 1,
        'count': 1,
        'dramas': [
          {'id': 'hongguo:1', 'source': 'hongguo'},
        ],
      }),
    );
    expect(document['count'], 1);
    expect((document['dramas'] as List), hasLength(1));
    expect(
      () => parseLibraryPackage(jsonEncode({'version': 2, 'dramas': []})),
      throwsA(isA<AppFailure>()),
    );
  });

  testWidgets('the lock screen offers library transfer without a password', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profiles': jsonEncode([
        {
          'id': 'owner',
          'name': '机主',
          'admin': true,
          'protected': true,
          'pin': 'pbkdf2\$1000\$c2FsdA==\$aGFzaA==',
        },
      ]),
      'profile': 'owner',
      'source': 'hongguo',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    final repository = LibraryProbeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilesScreen(
          store: store,
          locked: true,
          repository: repository,
        ),
      ),
    );
    expect(find.text('剧库导入导出'), findsOneWidget);
    expect(find.text('导出剧库'), findsOneWidget);
    expect(find.text('导入剧库'), findsOneWidget);
    expect(find.textContaining('不需要登录'), findsOneWidget);
    expect(find.text('添加用户'), findsNothing);
    expect(find.text('管理员 · 全部权限'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}

class LibraryProbeRepository extends FixtureRepository {
  @override
  Future<Uint8List> exportLibraryPackage() async =>
      Uint8List.fromList(const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]);

  @override
  int libraryPackageCount = 3;
}

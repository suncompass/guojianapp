import 'dart:async';

import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/interface_fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'catalog feedback, poster alignment and download layout on device',
    (tester) async {
      expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = InterfaceRepository();

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 400));
        debugPrint('APPEARANCE_CAPTURE $name');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await binding.takeScreenshot(name);
      }

      await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
      await tester.pumpAndSettle();
      expect(store.themeMode, 'system');
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).brightness,
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      );
      final covers = find.byType(DramaCover);
      final firstCover = tester.getRect(covers.first);
      for (var index = 1; index < 3; index++) {
        expect(
          tester.getRect(covers.at(index)).bottom,
          closeTo(firstCover.bottom, .01),
        );
      }
      await binding.convertFlutterSurfaceToImage();
      await capture('interface-system-catalog');

      final pending = Completer<CatalogPage>();
      repository.pendingCatalog = pending;
      final refresh = find.byKey(const ValueKey('catalog-refresh'));
      await tester.tap(refresh);
      await tester.pump();
      final rotation = find.descendant(
        of: refresh,
        matching: find.byType(RotationTransition),
      );
      final angle = tester.widget<RotationTransition>(rotation).turns.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<RotationTransition>(rotation).turns.value,
        isNot(angle),
      );
      await capture('interface-refreshing');
      repository.pendingCatalog = null;
      pending.complete(CatalogPage(repository.dramas('hongguo')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('更新剧库'), findsOneWidget);

      expect(find.text('黄豆'), findsNothing);
      expect(find.text('红果'), findsOneWidget);
      await store.setThemeMode('dark');
      await tester.pumpAndSettle();
      await capture('interface-dark-catalog');
      // 导航顺序为 主页 / 追剧 / 历史 / 下载，下载页是第 4 项。
      await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
      await tester.pumpAndSettle();
      await capture('interface-dark-downloads');
      await store.setThemeMode('light');
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('download-queue-actions'));
      // 筛选改成了对话框入口，这里只断言工具栏整体位于任务列表之上。
      final filters = find.byTooltip('筛选下载合集');
      final firstTask = find.byKey(const ValueKey('download-task-task-0'));
      expect(
        tester.getRect(menu).bottom,
        lessThan(tester.getRect(firstTask).top),
      );
      expect(
        tester.getRect(filters).bottom,
        lessThan(tester.getRect(firstTask).top),
      );
      await capture('interface-light-downloads');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await capture('interface-download-queue-menu');
      await tester.tap(find.text('全部暂停'));
      await tester.pumpAndSettle();
      expect(repository.jobs.where((job) => job.active), isEmpty);
      await tester.tap(filters);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '已下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '应用'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('download-task-task-0')), findsNothing);
      await capture('interface-completed-downloads');
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!['interface'] = {
        'systemThemeByDefault': true,
        'refreshAnimation': true,
        'alignedPosters': true,
        'vipOnlyOnHongguo': true,
        'downloadMenuAboveFilters': true,
        'bulkPause': true,
        'downloadFilter': true,
        'remoteImagesDisabled': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      store.dispose();
    },
  );
}

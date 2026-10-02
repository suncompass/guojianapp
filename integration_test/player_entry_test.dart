import 'dart:async';

import 'package:duanju_app/android_video_surface.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_route.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/search_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/fixtures.dart';

class EntryRepository extends FixtureRepository {
  int searches = 0;
  final pending = Completer<CatalogPage>();
  Completer<void>? playbackReady;

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) {
    searches++;
    return pending.future;
  }

  @override
  Future<CatalogPage> searchProgress(String source, String query) async =>
      CatalogPage([FixtureRepository.free]);

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    await playbackReady?.future;
    return const PlaybackPlan(url: 'http://127.0.0.1:18766/long.mp4');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('player entry, surface bounds and silent recommendations', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    const baseline = bool.fromEnvironment('ENTRY_BASELINE');
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    SearchResultCache.instance.clear();
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      store.dispose();
    });
    final repository = EntryRepository();
    final detail = await repository.detail(FixtureRepository.free);
    final navigator = GlobalKey<NavigatorState>();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        theme: AppTheme.light,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: 280,
                child: TextField(
                  key: ValueKey('entry-search'),
                  decoration: InputDecoration(labelText: '合成搜索输入'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    Future<void> open() async {
      final playbackReady = Completer<void>();
      repository.playbackReady = playbackReady;
      await tester.showKeyboard(find.byKey(const ValueKey('entry-search')));
      await tester.pump(const Duration(seconds: 1));
      debugPrint('ENTRY_KEYBOARD ${tester.view.viewInsets.bottom}');
      final bounds = <Rect>[];
      final tabs = <double>[];
      void recordBounds() {
        final surface = find.byKey(const ValueKey('player-gesture-surface'));
        if (surface.evaluate().isNotEmpty) {
          bounds.add(tester.getRect(surface));
          tabs.add(tester.getTopLeft(find.text('选集')).dy);
        }
      }

      unawaited(
        navigator.currentState!.push(
          playerRoute(
            PlayerScreen(
              detail: detail,
              initialIndex: 0,
              repository: repository,
              store: store,
            ),
          ),
        ),
      );
      final timer = Stopwatch()..start();
      while (find.byType(VideoSurfaceHost).evaluate().isEmpty) {
        if (timer.elapsed > const Duration(seconds: 20)) {
          fail('surface missing');
        }
        await tester.pump(const Duration(milliseconds: 16));
        recordBounds();
      }
      final player = tester
          .widget<VideoSurfaceHost>(find.byType(VideoSurfaceHost))
          .player;
      await player.setVolume(0);
      if (!baseline) {
        expect(find.text('正在准备播放'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byTooltip('暂停播放'), findsNothing);
        expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
      }
      debugPrint('ENTRY_CAPTURE loading');
      final loading = Stopwatch()..start();
      while (loading.elapsed < const Duration(seconds: 4)) {
        await tester.pump(const Duration(milliseconds: 16));
        recordBounds();
      }
      playbackReady.complete();
      final errors = <String>[];
      final errorsSubscription = player.stream.error.listen(errors.add);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        recordBounds();
      }
      final ready = Stopwatch()..start();
      while (player.state.position == Duration.zero &&
          ready.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 100));
        recordBounds();
      }
      debugPrint('ENTRY_BOUNDS ${bounds.toSet()}');
      debugPrint('ENTRY_TABS ${tabs.toSet()}');
      debugPrint('ENTRY_POSITION ${player.state.position} errors=$errors');
      await errorsSubscription.cancel();
      if (!baseline) {
        expect(bounds.toSet(), hasLength(1));
        expect(tabs.toSet(), hasLength(1));
        expect(bounds.first.top, 0);
      }
      debugPrint('ENTRY_CAPTURE playing');
      await tester.pump(const Duration(seconds: 2));
      expect(player.state.position, greaterThan(Duration.zero));
      debugPrint('ENTRY_CAPTURE motion');
      await tester.pump(const Duration(seconds: 2));
      await player.pause();
    }

    await open();
    await tester.tap(find.text('推荐'));
    await tester.pump(const Duration(seconds: 2));
    debugPrint(
      'ENTRY_PROGRESS ${find.byType(LinearProgressIndicator).evaluate().length}',
    );
    if (!baseline) {
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    debugPrint('ENTRY_CAPTURE recommendations');
    await tester.pump(const Duration(seconds: 12));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('选集'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('推荐'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repository.searches, 1);
    repository.pending.complete(CatalogPage([FixtureRepository.free]));
    await tester.pump(const Duration(seconds: 1));
    navigator.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
    await open();
    await tester.tap(find.text('推荐'));
    await tester.pump(const Duration(seconds: 2));
    debugPrint('ENTRY_SEARCHES ${repository.searches}');
    if (!baseline) expect(repository.searches, 1);
    debugPrint('ENTRY_CAPTURE cached');
    await tester.pump(const Duration(seconds: 12));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

import 'dart:async';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/search_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

class RecommendationRepository extends RouteRepository {
  final searches = <Completer<CatalogPage>>[];
  List<Drama> partial = [];

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) {
    final pending = Completer<CatalogPage>();
    searches.add(pending);
    return pending.future;
  }

  @override
  Future<CatalogPage> searchProgress(String source, String query) async =>
      CatalogPage(partial);
}

class DeferredPlaybackRepository extends RouteRepository {
  final ready = Completer<void>();

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    await ready.future;
    return super.resolve(drama, episode, quality: quality);
  }
}

void main() {
  setUp(SearchResultCache.instance.clear);

  Future<void> settleOperations(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    RouteRepository repository,
    ScriptedPlayer platform, {
    Size? size,
    FakeViewPadding? padding,
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues({});
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
    }
    if (padding != null) {
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
    }
    final store = LocalStore(await SharedPreferences.getInstance());
    final detail = await repository.detail(FixtureRepository.free);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.dark(),
        home: PlayerScreen(
          detail: detail,
          initialIndex: 0,
          initialPosition: 7,
          repository: repository,
          store: store,
          playerFactory: () => Player(platformPlayer: platform),
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    await settleOperations(tester);
  }

  Future<void> unmount(WidgetTester tester, ScriptedPlayer player) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
    await settleOperations(tester);
    expect(player.disposed, isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'duplicate errors switch once while keeping progress, rate and pause state',
    (tester) async {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      await tester.tap(find.byKey(const ValueKey('player-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭菜单'));
      await tester.pumpAndSettle();
      await player.seek(const Duration(seconds: 28));
      await tester.pump();
      await tester.tap(find.byTooltip('暂停播放'));
      await settleOperations(tester);
      player.fail();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOperations(tester);
      expect(repository.fallbackCalls, 1);
      expect(repository.primaryCalls, 1);
      expect(player.opened.last.start, const Duration(seconds: 28));
      expect(player.state.rate, 1.5);
      expect(player.played.last, isFalse);
      expect(repository.active.length, 1);
      expect(find.text('暂时无法播放'), findsNothing);
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets(
    'recovery exhaustion releases sessions and manual retry keeps the saved position',
    (tester) async {
      final repository = RouteRepository()..broken = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        await settleOperations(tester);
      }
      expect(repository.primaryCalls, 2);
      expect(repository.fallbackCalls, 2);
      expect(find.text('暂时无法播放'), findsOneWidget);
      expect(repository.active, isEmpty);
      await tester.pump(const Duration(seconds: 25));
      expect(repository.primaryCalls + repository.fallbackCalls, 4);
      repository.broken = false;
      await tester.tap(find.text('重试播放'));
      await settleOperations(tester);
      expect(player.opened.last.start, const Duration(seconds: 7));
      expect(find.text('暂时无法播放'), findsNothing);
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets(
    'switching episodes ignores a delayed fallback and frees both old plans',
    (tester) async {
      final repository = RouteRepository()..deferFallback = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      player.fail();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOperations(tester);
      expect(repository.pending, isNotNull);
      await tester.tap(find.byKey(const ValueKey('play-episode-2')));
      await settleOperations(tester);
      final currentURL = player.opened.last.uri;
      final late = PlaybackPlan(
        url: 'https://media.test/late.mp4',
        session: 'late',
      );
      repository.active.add(late.session);
      repository.pending!.complete(late);
      await settleOperations(tester);
      expect(player.opened.last.uri, currentURL);
      expect(repository.active.length, 1);
      expect(repository.active, isNot(contains('late')));
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets('picture-in-picture hides app overlay controls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
      switch (call.method) {
        case 'pictureInPictureStatus':
          return {'supported': true, 'active': false};
        case 'enterPictureInPicture':
          return {'supported': true, 'active': true, 'requested': true};
      }
      return null;
    });
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      expect(
        find.byKey(const ValueKey('player-picture-in-picture')),
        findsOneWidget,
      );
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('player-picture-in-picture')));
      await tester.pump();
      await tester.pump();
      await settleOperations(tester);
      expect(
        find.byKey(const ValueKey('player-picture-in-picture')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('player-speed')), findsNothing);
      expect(find.byKey(const ValueKey('player-quality')), findsNothing);
      expect(find.byKey(const ValueKey('player-progress')), findsNothing);
      expect(find.text('选集'), findsNothing);
      expect(find.text('简介'), findsNothing);
      expect(find.text('下载'), findsNothing);
      await unmount(tester, player);
    } finally {
      messenger.setMockMethodCallHandler(AppDevice.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'mobile video reaches the top while buttons avoid the status area',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final repository = RouteRepository();
        final player = ScriptedPlayer();
        await mount(
          tester,
          repository,
          player,
          size: const Size(390, 844),
          padding: const FakeViewPadding(top: 32, bottom: 24),
        );
        final surface = tester.getRect(
          find.byKey(const ValueKey('player-gesture-surface')),
        );
        expect(surface.top, 0);
        final back = tester.getRect(find.byTooltip('返回'));
        expect(back.top, greaterThanOrEqualTo(32));
        player.videoSize(1920, 1080);
        await settleOperations(tester);
        expect(
          tester.getRect(find.byKey(const ValueKey('player-gesture-surface'))),
          surface,
        );
        tester.view.padding = const FakeViewPadding(top: 32);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await settleOperations(tester);
        expect(
          tester.getRect(find.byKey(const ValueKey('player-gesture-surface'))),
          surface,
        );
        player.videoSize(1080, 1920);
        await settleOperations(tester);
        expect(
          tester.getRect(find.byKey(const ValueKey('player-gesture-surface'))),
          surface,
        );
        await unmount(tester, player);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
      }
    },
  );

  testWidgets(
    'loading and buffering use readable text without overlapping playback controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final repository = DeferredPlaybackRepository();
        final player = ScriptedPlayer();
        await mount(
          tester,
          repository,
          player,
          size: const Size(390, 844),
          theme: ThemeData.light(),
        );
        final loading = find.text('正在准备播放');
        expect(loading, findsOneWidget);
        expect(tester.widget<Text>(loading).style?.color, Colors.white70);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byTooltip('暂停播放'), findsNothing);
        expect(find.byTooltip('开始播放'), findsNothing);
        expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
        repository.ready.complete();
        await settleOperations(tester);
        expect(loading, findsNothing);
        expect(find.byTooltip('暂停播放'), findsOneWidget);
        player.setBuffering(true);
        await settleOperations(tester);
        expect(find.text('正在缓冲'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byTooltip('暂停播放'), findsNothing);
        player.setBuffering(false);
        await settleOperations(tester);
        expect(find.text('正在缓冲'), findsNothing);
        expect(find.byTooltip('暂停播放'), findsOneWidget);
        await unmount(tester, player);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'fresh recommendations survive tab switches and reopening without searches',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SearchResultCache.instance.write(
          SearchCacheEntry(
            source: 'hongguo',
            query: FixtureRepository.free.title,
            items: [FixtureRepository.free],
            total: 1,
            storedAt: DateTime.now().subtract(const Duration(minutes: 19)),
          ),
        );
        final repository = RecommendationRepository();
        for (var opening = 0; opening < 2; opening++) {
          final player = ScriptedPlayer();
          await mount(tester, repository, player, size: const Size(390, 844));
          for (var tab = 0; tab < 3; tab++) {
            await tester.tap(find.text('推荐'));
            await settleOperations(tester);
            expect(
              find.byKey(const ValueKey('recommend-hongguo:100')),
              findsOneWidget,
            );
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            await tester.tap(find.text('选集'));
            await settleOperations(tester);
          }
          expect(repository.searches, isEmpty);
          await unmount(tester, player);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'expired recommendations stay visible during one silent refresh',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final cache = SearchResultCache.instance;
        cache.write(
          SearchCacheEntry(
            source: 'hongguo',
            query: FixtureRepository.free.title,
            items: [FixtureRepository.free],
            total: 1,
            storedAt: DateTime.now().subtract(const Duration(minutes: 21)),
          ),
        );
        final repository = RecommendationRepository();
        final player = ScriptedPlayer();
        await mount(tester, repository, player, size: const Size(390, 844));
        await tester.tap(find.text('推荐'));
        await settleOperations(tester);
        expect(
          find.byKey(const ValueKey('recommend-hongguo:100')),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('选集'));
        await tester.pump();
        await tester.tap(find.text('推荐'));
        await tester.pump();
        expect(repository.searches, hasLength(1));
        repository.searches.single.complete(
          CatalogPage([FixtureRepository.free]),
        );
        await settleOperations(tester);
        expect(
          cache.read('hongguo', FixtureRepository.free.title)?.fresh,
          isTrue,
        );
        await unmount(tester, player);
        final reopened = ScriptedPlayer();
        await mount(tester, repository, reopened, size: const Size(390, 844));
        await tester.tap(find.text('推荐'));
        await settleOperations(tester);
        expect(repository.searches, hasLength(1));
        await unmount(tester, reopened);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'silent first recommendations stream in and cache empty results',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final repository = RecommendationRepository();
        final player = ScriptedPlayer();
        await mount(tester, repository, player, size: const Size(390, 844));
        await tester.tap(find.text('推荐'));
        await settleOperations(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        repository.partial = [FixtureRepository.free];
        await tester.pump(const Duration(seconds: 1));
        await settleOperations(tester);
        expect(
          find.byKey(const ValueKey('recommend-hongguo:100')),
          findsOneWidget,
        );
        repository.searches.single.complete(CatalogPage([]));
        await settleOperations(tester);
        expect(
          find.byKey(const ValueKey('recommend-hongguo:100')),
          findsNothing,
        );
        await unmount(tester, player);
        final reopened = ScriptedPlayer();
        await mount(tester, repository, reopened, size: const Size(390, 844));
        await tester.tap(find.text('推荐'));
        await settleOperations(tester);
        expect(repository.searches, hasLength(1));
        expect(find.text('暂无可推荐的相关剧集'), findsOneWidget);
        await unmount(tester, reopened);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('compact player tools stay clustered instead of evenly spread', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
      if (call.method == 'pictureInPictureStatus') {
        return {'supported': true, 'active': false};
      }
      return null;
    });
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      final speed = tester.getRect(find.byKey(const ValueKey('player-speed')));
      final quality = tester.getRect(
        find.byKey(const ValueKey('player-quality')),
      );
      final pip = tester.getRect(
        find.byKey(const ValueKey('player-picture-in-picture')),
      );
      expect(quality.left - speed.right, lessThan(8));
      expect(pip.left - quality.right, lessThan(8));
      expect(pip.right, greaterThan(330));
      await unmount(tester, player);
    } finally {
      messenger.setMockMethodCallHandler(AppDevice.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('losing window focus keeps playback running', (tester) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await mount(tester, repository, player);
    expect(player.state.playing, isTrue);
    final baseline = player.pauses;

    Future<void> lifecycle(AppLifecycleState state) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.lifecycle.name,
        const StringCodec().encodeMessage('AppLifecycleState.${state.name}'),
        (_) {},
      );
      await settleOperations(tester);
    }

    await lifecycle(AppLifecycleState.inactive);
    expect(
      player.pauses,
      baseline,
      reason: 'Android 的 inactive 对应 Activity.onPause，音量面板等临时遮挡不应暂停播放',
    );
    expect(player.state.playing, isTrue);

    await lifecycle(AppLifecycleState.resumed);
    expect(player.pauses, baseline);
    expect(player.state.playing, isTrue);

    await lifecycle(AppLifecycleState.hidden);
    expect(player.pauses, greaterThan(baseline), reason: '真正隐藏后才暂停');
    expect(player.state.playing, isFalse);

    await lifecycle(AppLifecycleState.paused);
    expect(player.state.playing, isFalse);

    await lifecycle(AppLifecycleState.resumed);
    expect(player.state.playing, isFalse, reason: '回到前台不自动续播，交由用户决定');
    await unmount(tester, player);
  });
}

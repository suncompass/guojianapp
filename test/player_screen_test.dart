import 'dart:async';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/player_controls.dart';
import 'package:duanju_app/player_episode_transition.dart';
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

class DownloadingRepository extends RouteRepository {
  final jobs = <DownloadJob>[];

  @override
  bool get supportsDownloads => true;

  @override
  Future<List<DownloadJob>> downloads() async => List.of(jobs);
}

class _TransitionRepository extends RouteRepository {
  final nextReady = Completer<void>();
  final cleanupReady = Completer<void>();
  final releases = <String>[];
  String? blockedRelease;
  int nextRequests = 0;

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    if (episode.number == 2) {
      nextRequests++;
      await nextReady.future;
    }
    return super.resolve(drama, episode, quality: quality);
  }

  @override
  Future<void> release(String session) async {
    releases.add(session);
    if (session == blockedRelease) await cleanupReady.future;
    await super.release(session);
  }
}

class _TransitionPlayer extends ScriptedPlayer {
  int stops = 0;
  Completer<void>? openGate;

  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final gate = openGate;
    if (gate != null) await gate.future;
    await super.open(playable, play: play);
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
    VoidCallback? onVideoBuild,
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
          videoBuilder: (controls) {
            onVideoBuild?.call();
            return controls;
          },
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

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform portrait panel collapses without restarting playback',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final repository = RouteRepository();
          final player = ScriptedPlayer();
          await mount(
            tester,
            repository,
            player,
            size: const Size(390, 844),
            padding: const FakeViewPadding(top: 32, bottom: 24),
            theme: ThemeData.light(),
          );
          final surface = find.byKey(const ValueKey('player-gesture-surface'));
          final episode = find.byKey(const ValueKey('play-episode-2'));
          final toggle = find.byKey(const ValueKey('player-panel-toggle'));
          final background = find.byKey(
            const ValueKey('player-panel-background'),
          );
          expect(tester.widget<Material>(background).color, Colors.black);
          final panelTheme = Theme.of(tester.element(episode));
          expect(panelTheme.brightness, Brightness.dark);
          expect(panelTheme.colorScheme.surface, Colors.black);
          final expandedRect = tester.getRect(surface);
          final surfaceElement = tester.element(surface);
          final episodeElement = tester.element(episode);
          final opened = player.opened.length;
          await player.seek(const Duration(seconds: 28));
          await player.setRate(1.5);
          await tester.pump();
          expect(find.text('收起'), findsOneWidget);

          await tester.tap(toggle);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 110));
          expect(episode, findsOneWidget, reason: '收起过程中内容不能提前消失');
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(milliseconds: 220));
          final collapsedRect = tester.getRect(surface);
          expect(collapsedRect.top, 0);
          expect(collapsedRect.height, greaterThan(expandedRect.height));
          expect(collapsedRect.bottom, closeTo(844 - 24 - 48, .01));
          expect(tester.getRect(toggle).bottom, lessThanOrEqualTo(844 - 24));
          expect(find.text('第 1 集 · 共 2 集'), findsOneWidget);
          expect(tester.widget<Material>(background).color, Colors.black);
          expect(find.text('展开'), findsOneWidget);
          expect(find.text('简介'), findsNothing);
          expect(episode, findsNothing);
          expect(tester.element(surface), same(surfaceElement));
          expect(player.opened, hasLength(opened));
          expect(player.state.position, const Duration(seconds: 28));
          expect(player.state.rate, 1.5);
          expect(player.state.playing, isTrue);

          await tester.tap(toggle);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 220));
          expect(
            tester.getRect(surface).height,
            closeTo(expandedRect.height, .01),
          );
          expect(tester.element(episode), same(episodeElement));
          expect(find.text('收起'), findsOneWidget);
          expect(player.opened, hasLength(opened));
          await tester.tap(episode);
          await settleOperations(tester);
          expect(repository.requestedEpisodes.last, 2);
          await unmount(tester, player);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  for (final initiallyVisible in [true, false]) {
    testWidgets('hold hides controls from visible=$initiallyVisible', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final repository = RouteRepository();
        final player = ScriptedPlayer();
        await mount(tester, repository, player, size: const Size(390, 844));
        final surface = find.byKey(const ValueKey('player-gesture-surface'));
        final chrome = find.byKey(const ValueKey('player-controls-chrome'));
        final controls = tester.widget<PlayerControls>(
          find.byType(PlayerControls),
        );
        final position = player.state.position;
        for (final x in [.1, .5, .9]) {
          await tester.pump(const Duration(milliseconds: 700));
          final rect = tester.getRect(surface);
          final point = rect.topLeft + Offset(rect.width * x, rect.height * .3);
          final visible = tester.widget<AnimatedOpacity>(chrome).opacity == 1;
          if (visible != initiallyVisible) {
            await tester.tapAt(point);
            await tester.pump(const Duration(milliseconds: 350));
          }
          expect(
            tester.widget<AnimatedOpacity>(chrome).opacity,
            initiallyVisible ? 1 : 0,
          );
          final gesture = await tester.startGesture(point);
          await tester.pump(const Duration(milliseconds: 400));
          await controls.interactions.pendingRates;
          expect(player.state.rate, 2);
          expect(player.state.position, position, reason: '长按任何区域都不能跳进度');
          expect(find.text('2 倍速 · 松开恢复'), findsOneWidget);
          expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
          expect(find.byTooltip('暂停播放').hitTestable(), findsNothing);
          // 缓冲事件也不能在长按期间重新唤醒控制栏。
          player.setBuffering(true);
          await tester.pump();
          expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
          player.setBuffering(false);
          await tester.pump();
          await gesture.up();
          await tester.pump();
          await controls.interactions.pendingRates;
          expect(player.state.rate, 1);
          expect(player.state.playing, isTrue);
          expect(controls.interactions.suppressTap, isTrue);
          expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
          await tester.pump(const Duration(milliseconds: 1300));
          expect(controls.interactions.suppressTap, isFalse);
          expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
          expect(find.text('恢复 1.0 倍速'), findsNothing);
        }
        // 主动轻点仍可唤出控制栏，不把隐藏状态锁死。
        await tester.tapAt(
          tester.getRect(surface).topLeft + const Offset(80, 100),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);
        await unmount(tester, player);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final portraitVideo in [true, false]) {
    testWidgets('fullscreen retains state portrait=$portraitVideo', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final orientations = <List<String>>[];
      final panelsAtOrientationRequest = <bool>[];
      final episodeKey = const ValueKey('play-episode-2');
      // 只有选集按钮真实存在过，才能用它的消失证明面板没有残留。
      bool panelMounted() {
        final found = find.byKey(episodeKey, skipOffstage: false);
        return found.evaluate().isNotEmpty;
      }

      final messenger = tester.binding.defaultBinaryMessenger;
      // Widget 测试没有真实系统旋转回包，显式完成平台调用以释放旋转锁。
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          // 系统在这一刻对窗口取快照，此时必须已经画过没有面板的帧。
          panelsAtOrientationRequest.add(panelMounted());
          orientations.add(List<String>.from(call.arguments as List));
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      try {
        final repository = RouteRepository();
        final player = ScriptedPlayer();
        await mount(tester, repository, player, size: const Size(390, 844));
        player.videoSize(
          portraitVideo ? 1080 : 1920,
          portraitVideo ? 1920 : 1080,
        );
        await settleOperations(tester);
        await tester.pump(const Duration(seconds: 4));
        final controlFinder = find.byType(PlayerControls);
        final controlState = tester.state(controlFinder);
        final controls = tester.widget<PlayerControls>(controlFinder);
        final surface = find.byKey(const ValueKey('player-gesture-surface'));
        final surfaceElement = tester.element(surface);
        final chrome = find.byKey(const ValueKey('player-controls-chrome'));
        final opened = player.opened.length;
        final position = player.state.position;
        final initialHeight = tester.getSize(surface).height;
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
        expect(panelMounted(), isTrue, reason: '进入全屏前必须实际存在选集，避免断言空跑');
        controls.onFullscreen();
        await tester.pump();
        expect(panelMounted(), isFalse, reason: '进入全屏的首帧不能保留选集内容');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(tester.getSize(surface).height, greaterThan(initialHeight));
        // 旋转请求发出时窗口快照已生成，树里必须没有选集内容。
        expect(panelsAtOrientationRequest, isNotEmpty);
        expect(
          panelsAtOrientationRequest.first,
          isFalse,
          reason: '系统旋转前必须先绘制不含选集面板的帧',
        );
        if (!portraitVideo) {
          tester.view.physicalSize = const Size(844, 390);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(panelMounted(), isFalse, reason: '横屏稳定后也不能挂载选集内容');
        expect(tester.widget<PlayerControls>(controlFinder).fullscreen, isTrue);
        expect(orientations, hasLength(1));
        expect(orientations.single, hasLength(2));
        expect(tester.state(controlFinder), same(controlState));
        expect(tester.element(surface), same(surfaceElement));
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
        expect(find.byKey(const ValueKey('player-panel-toggle')), findsNothing);
        tester.widget<PlayerControls>(controlFinder).onFullscreen();
        await tester.pump();
        tester.view.physicalSize = const Size(390, 844);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(
          tester.widget<PlayerControls>(controlFinder).fullscreen,
          isFalse,
        );
        expect(orientations, hasLength(2));
        expect(
          orientations.last,
          DeviceOrientation.values.map((value) => value.toString()).toList(),
        );
        expect(tester.state(controlFinder), same(controlState));
        expect(tester.element(surface), same(surfaceElement));
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
        expect(tester.getSize(surface).height, closeTo(initialHeight, .01));
        expect(player.opened, hasLength(opened));
        expect(player.state.position, position);
        expect(player.state.playing, isTrue);
        await unmount(tester, player);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('panel animation does not rebuild the video on each frame', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      var builds = 0;
      await mount(
        tester,
        repository,
        player,
        size: const Size(390, 844),
        onVideoBuild: () => builds++,
      );
      await settleOperations(tester);
      final toggle = find.byKey(const ValueKey('player-panel-toggle'));
      final surface = find.byKey(const ValueKey('player-gesture-surface'));
      for (var transition = 0; transition < 2; transition++) {
        await tester.tap(toggle);
        await tester.pump();
        final initialBuilds = builds;
        final height = tester.getSize(surface).height;
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(builds, initialBuilds);
        expect(tester.getSize(surface).height, isNot(height));
        await tester.pump(const Duration(milliseconds: 220));
      }
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('panel animation can reverse before collapse completes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      final toggle = find.byKey(const ValueKey('player-panel-toggle'));
      final episode = find.byKey(const ValueKey('play-episode-2'));
      final element = tester.element(episode);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.element(episode), same(element));
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.element(episode), same(element));
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(episode, findsNothing);
      expect(find.text('展开'), findsOneWidget);
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('collapsing preserves the selected tab and paused playback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(320, 640));
      await tester.tap(find.text('简介'));
      await settleOperations(tester);
      final follow = find.byKey(const ValueKey('player-follow-status'));
      final followElement = tester.element(follow);
      await player.pause();
      await tester.pump();
      final opened = player.opened.length;
      final toggle = find.byKey(const ValueKey('player-panel-toggle'));
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(follow, findsNothing);
      expect(find.text('展开'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.element(follow), same(followElement));
      expect(player.state.playing, isFalse);
      expect(player.opened, hasLength(opened));
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('auto advance keeps media until replacement and defers cleanup', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = _TransitionRepository();
      final player = _TransitionPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      final previous = repository.active.single;
      repository.blockedRelease = previous;
      addTearDown(() {
        if (!repository.cleanupReady.isCompleted) {
          repository.cleanupReady.complete();
        }
      });
      final stops = player.stops;
      player.finishEpisode();
      await settleOperations(tester);
      expect(repository.nextRequests, 1);
      expect(player.stops, stops);
      expect(player.state.position, player.state.duration);
      expect(repository.active, contains(previous));
      expect(find.byKey(const ValueKey('player-loading-mask')), findsNothing);
      expect(find.text('正在准备播放'), findsNothing);
      expect(find.text('即将播放 · 第 2 集'), findsNothing);
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.text('即将播放 · 第 2 集'), findsOneWidget);
      // 重复的旧 completed 事件不能再发起一次解析。
      player.finishEpisode();
      await settleOperations(tester);
      expect(repository.nextRequests, 1);

      player.openGate = Completer<void>();
      repository.nextReady.complete();
      await settleOperations(tester);
      expect(player.opened, hasLength(1));
      expect(repository.releases, isNot(contains(previous)));
      player.openGate!.complete();
      await settleOperations(tester);
      expect(player.opened, hasLength(2));
      expect(player.stops, stops);
      expect(player.state.playing, isTrue);
      expect(repository.releases, contains(previous));
      expect(repository.active, contains(previous));
      // 旧会话清理被阻塞也不影响下一集打开；首段进度推进后提示才退场。
      expect(
        tester
            .widget<PlayerEpisodeTransition>(
              find.byType(PlayerEpisodeTransition),
            )
            .episodeNumber,
        2,
      );
      player.setBuffering(true);
      await player.seek(const Duration(milliseconds: 250));
      await settleOperations(tester);
      expect(find.text('正在缓冲'), findsNothing);
      expect(
        tester
            .widget<PlayerEpisodeTransition>(
              find.byType(PlayerEpisodeTransition),
            )
            .episodeNumber,
        2,
      );
      player.setBuffering(false);
      await settleOperations(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('即将播放 · 第 2 集'), findsNothing);
      repository.cleanupReady.complete();
      await settleOperations(tester);
      expect(repository.active, hasLength(1));
      player.finishEpisode();
      await settleOperations(tester);
      expect(player.opened, hasLength(2), reason: '最后一集不再启动切换');
      expect(player.state.playing, isFalse);
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('manual selection supersedes a pending automatic transition', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = _TransitionRepository();
      final player = _TransitionPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      player.finishEpisode();
      await settleOperations(tester);
      await tester.tap(find.byKey(const ValueKey('play-episode-1')));
      await settleOperations(tester);
      expect(player.opened, hasLength(2));
      final current = player.opened.last.uri;
      repository.nextReady.complete();
      await settleOperations(tester);
      expect(player.opened.last.uri, current);
      expect(player.opened, hasLength(2));
      expect(repository.active, hasLength(1));
      expect(
        tester
            .widget<PlayerEpisodeTransition>(
              find.byType(PlayerEpisodeTransition),
            )
            .episodeNumber,
        isNull,
      );
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('auto advance failure clears the transition hint', (
    tester,
  ) async {
    final repository = _TransitionRepository();
    final player = _TransitionPlayer();
    await mount(tester, repository, player);
    player.finishEpisode();
    await settleOperations(tester);
    repository.nextReady.completeError(StateError('unavailable'));
    await settleOperations(tester);
    expect(find.text('暂时无法播放'), findsOneWidget);
    expect(
      tester
          .widget<PlayerEpisodeTransition>(find.byType(PlayerEpisodeTransition))
          .episodeNumber,
      isNull,
    );
    await unmount(tester, player);
    expect(repository.active, isEmpty);
  });

  testWidgets('leaving during automatic preparation releases the late plan', (
    tester,
  ) async {
    final repository = _TransitionRepository();
    final player = _TransitionPlayer();
    await mount(tester, repository, player);
    player.finishEpisode();
    await settleOperations(tester);
    await unmount(tester, player);
    repository.nextReady.complete();
    await settleOperations(tester);
    expect(player.opened, hasLength(1));
    expect(repository.active, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed panel follows auto advance and survives rotation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      final toggle = find.byKey(const ValueKey('player-panel-toggle'));
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      player.finishEpisode();
      await settleOperations(tester);
      expect(find.text('第 2 集 · 共 2 集'), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);

      // 竖视频横屏仍使用原来的侧栏，不把竖屏折叠状态带入侧栏。
      player.videoSize(1080, 1920);
      await settleOperations(tester);
      tester.view.physicalSize = const Size(844, 390);
      await settleOperations(tester);
      expect(toggle, findsNothing);
      expect(find.byKey(const ValueKey('play-episode-2')), findsOneWidget);

      // 横视频横屏仍为全屏播放，也不显示折叠入口。
      player.videoSize(1920, 1080);
      await settleOperations(tester);
      await tester.pump(const Duration(milliseconds: 220));
      expect(toggle, findsNothing);
      expect(find.byKey(const ValueKey('play-episode-2')), findsNothing);
      tester.view.physicalSize = const Size(390, 844);
      await settleOperations(tester);
      expect(find.text('展开'), findsOneWidget);
      expect(find.text('第 2 集 · 共 2 集'), findsOneWidget);
      expect(find.byKey(const ValueKey('play-episode-2')), findsNothing);
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('collapsed panel keeps download progress reachable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = DownloadingRepository();
      final player = ScriptedPlayer();
      final detail = await repository.detail(FixtureRepository.free);
      repository.jobs.add(
        DownloadJob(
          id: 'job-1',
          drama: detail.drama,
          episode: detail.episodes.first,
          state: 'downloading',
          progress: .4,
        ),
      );
      await mount(tester, repository, player, size: const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('player-panel-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await settleOperations(tester);
      // 收起后详情面板里的下载进度不可见，头部角标要顶上。
      expect(
        find.byKey(const ValueKey('player-download-badge')),
        findsOneWidget,
      );
      expect(find.text('1 集 40%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player-download-badge')));
      await settleOperations(tester);
      expect(find.text('收起'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-download-badge')), findsNothing);
      // 角标点击后面板展开并直接落在下载页。
      expect(find.byKey(const ValueKey('enqueue-downloads')), findsOneWidget);
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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

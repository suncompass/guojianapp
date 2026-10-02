import 'dart:convert';
import 'dart:ui' show FramePhase;

import 'package:duanju_app/android_video_surface.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixtureBase = String.fromEnvironment('FIXTURE_BASE_URL');

class PerfRepository extends AppRepository {
  final native = NativeRepository();
  final resolved = <int>[];
  static const drama = Drama(
    id: 'hongguo:700001',
    source: 'hongguo',
    title: '设备性能验证',
    episodes: 3,
  );

  @override
  Future<void> initialize() => native.initialize();
  @override
  Future<CatalogPage> searchProgress(String source, String query) async =>
      CatalogPage([]);
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage([]);
  @override
  Future<String> cover(Drama drama, {bool force = false}) =>
      native.cover(drama, force: force);
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage([drama]);
  @override
  Future<DramaDetail> detail(Drama drama) async => DramaDetail(drama, [
    for (var number = 1; number <= 3; number++)
      Episode({
        'id': '$number',
        'source': 'hongguo',
        'currentEpisode': number,
        'title': '第$number集',
        'videoUrl': '$fixtureBase/long.mp4',
        'referer': '$fixtureBase/',
      }, number),
  ]);
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    final plan = await native.resolve(drama, episode, quality: quality);
    resolved.add(episode.number);
    return plan;
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) =>
      native.fallback(current);
  @override
  Future<void> cancelPlayback() => native.cancelPlayback();
  @override
  Future<void> release(String session) => native.release(session);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measure playback frame pacing', (tester) async {
    expect(fixtureBase, startsWith('http://127.0.0.1:'));
    MediaKit.ensureInitialized();
    final repository = PerfRepository();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());

    final samples = <int>[];
    final build = <int>[];
    final raster = <int>[];
    final spikes = <Map<String, int>>[];
    int? spikesBase;
    void collect(List<FrameTiming> timings) {
      for (final timing in timings) {
        final buildUs = timing.buildDuration.inMicroseconds;
        final stamp =
            timing.timestampInMicroseconds(FramePhase.vsyncStart) ~/ 1000;
        build.add(buildUs);
        raster.add(timing.rasterDuration.inMicroseconds);
        samples.add(timing.totalSpan.inMicroseconds);
        if (buildUs > 16000) {
          spikesBase ??= stamp;
          spikes.add({
            'ms': stamp - spikesBase!,
            'build': buildUs,
            'raster': timing.rasterDuration.inMicroseconds,
          });
        }
      }
    }

    Future<void> until(bool Function() ready, String step) async {
      final timer = Stopwatch()..start();
      while (!ready()) {
        if (timer.elapsed > const Duration(seconds: 40)) {
          fail('Timed out: $step');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Player player() {
      final surface = find.byType(VideoSurfaceHost).evaluate();
      if (surface.isNotEmpty) {
        return tester
            .widget<VideoSurfaceHost>(find.byType(VideoSurfaceHost))
            .player;
      }
      return tester.widget<Video>(find.byType(Video)).controller.player;
    }

    bool playerMounted() =>
        find.byType(Video).evaluate().isNotEmpty ||
        find.byType(VideoSurfaceHost).evaluate().isNotEmpty;

    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await until(() => find.text('设备性能验证').evaluate().isNotEmpty, 'catalog');
    await tester.tap(find.text('设备性能验证'));
    await until(playerMounted, 'player');
    await player().setVolume(0);

    await until(
      () =>
          (player().state.width ?? 0) > 0 &&
          player().state.position.inSeconds >= 2,
      'first frame',
    );

    binding.addTimingsCallback(collect);
    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 45)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    binding.removeTimingsCallback(collect);

    samples.sort();
    build.sort();
    raster.sort();
    int pct(List<int> values, double p) => values.isEmpty
        ? 0
        : values[(values.length * p).clamp(0, values.length - 1).toInt()];
    int over(List<int> values, int limit) =>
        values.where((value) => value > limit).length;

    final report = <String, Object?>{
      'frames': samples.length,
      'buildP50': pct(build, 0.5),
      'buildP90': pct(build, 0.9),
      'buildP99': pct(build, 0.99),
      'buildMax': build.isEmpty ? 0 : build.last,
      'rasterP50': pct(raster, 0.5),
      'rasterP90': pct(raster, 0.9),
      'rasterP99': pct(raster, 0.99),
      'rasterMax': raster.isEmpty ? 0 : raster.last,
      'spanP50': pct(samples, 0.5),
      'spanP90': pct(samples, 0.9),
      'spanP99': pct(samples, 0.99),
      'spanMax': samples.isEmpty ? 0 : samples.last,
      'buildOver16ms': over(build, 16000),
      'rasterOver16ms': over(raster, 16000),
      'spanOver33ms': over(samples, 33000),
      'buildOver100ms': over(build, 100000),
      'rasterOver100ms': over(raster, 100000),
      'finalPositionMs': player().state.position.inMilliseconds,
      'buildSpikes': spikes,
      'surfaceOutput': find.byType(VideoSurfaceHost).evaluate().isNotEmpty,
      'textureOutput': find.byType(Video).evaluate().isNotEmpty,
      'videoWidth': player().state.width ?? 0,
      'videoHeight': player().state.height ?? 0,
    };
    binding.reportData ??= {};
    binding.reportData!['perf'] = report;
    // ignore: avoid_print
    print('PERF ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}

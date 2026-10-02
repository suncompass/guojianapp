import 'package:duanju_app/android_video_surface.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixtureBase = String.fromEnvironment('FIXTURE_BASE_URL');

class LifeRepository extends AppRepository {
  final native = NativeRepository();
  static const drama = Drama(
    id: 'hongguo:700001',
    source: 'hongguo',
    title: 'SurfaceLifecycle',
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
  }) =>
      native.resolve(drama, episode, quality: quality);
  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) =>
      native.fallback(current);
  @override
  Future<void> cancelPlayback() => native.cancelPlayback();
  @override
  Future<void> release(String session) => native.release(session);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('surface survives background and resume', (tester) async {
    MediaKit.ensureInitialized();
    final repository = LifeRepository();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());

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

    bool mounted() =>
        find.byType(Video).evaluate().isNotEmpty ||
        find.byType(VideoSurfaceHost).evaluate().isNotEmpty;

    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await until(() => find.text('SurfaceLifecycle').evaluate().isNotEmpty,
        'catalog');
    await tester.tap(find.text('SurfaceLifecycle'));
    await until(mounted, 'player');
    await player().setVolume(0);
    await until(
      () =>
          (player().state.width ?? 0) > 0 &&
          player().state.position.inSeconds >= 2,
      'first frame',
    );

    final before = player().state.position;
    final mountedBefore = mounted();

    // Hold the surface open so an external HOME/return cycle can be applied.
    final hold = Stopwatch()..start();
    while (hold.elapsed < const Duration(seconds: 150)) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final after = player().state.position;
    // ignore: avoid_print
    print('LIFE ${{
      'mountedBefore': mountedBefore,
      'mountedAfter': mounted(),
      'surfaceAfter': find.byType(VideoSurfaceHost).evaluate().isNotEmpty,
      'textureAfter': find.byType(Video).evaluate().isNotEmpty,
      'beforeMs': before.inMilliseconds,
      'afterMs': after.inMilliseconds,
      'playedOn': after > before + const Duration(milliseconds: 500),
      'width': player().state.width ?? 0,
    }}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

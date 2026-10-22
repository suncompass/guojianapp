import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

final _episode = Episode({'id': '2', 'currentEpisode': 2}, 2);
const _plan = PlaybackPlan(
  url: 'https://media.test/preloaded.mp4',
  session: 'preloaded',
);

void main() {
  testWidgets('take hands over an in-flight preload without cancelling it', (
    tester,
  ) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    final taking = preloader.take(
      FixtureRepository.free,
      _episode,
      waitForPending: true,
    );
    expect(repository.preloadCancellations, 0);
    repository.preloads.single.complete(_plan);
    await tester.pump();
    expect(await taking, same(_plan));
    expect(repository.preloadCancellations, 0);
    expect(repository.releasedSessions, isEmpty);
    expect(await preloader.take(FixtureRepository.free, _episode), isNull);
    preloader.dispose();
  });

  testWidgets('take times out and releases a late preload exactly once', (
    tester,
  ) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    final taking = preloader.take(
      FixtureRepository.free,
      _episode,
      waitForPending: true,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(await taking, isNull);
    expect(repository.preloadCancellations, 1);
    repository.preloads.single.complete(_plan);
    await tester.pump();
    expect(repository.releasedSessions, [_plan.session]);
    preloader.dispose();
    expect(repository.releasedSessions, [_plan.session]);
  });

  testWidgets('cancelled take cannot clear a newer quality preload', (
    tester,
  ) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    final taking = preloader.take(
      FixtureRepository.free,
      _episode,
      waitForPending: true,
    );
    preloader.prepare(FixtureRepository.free, _episode, quality: 720);
    await tester.pump();
    expect(await taking, isNull);
    await tester.pump(const Duration(milliseconds: 600));
    expect(repository.preloads, hasLength(2));
    repository.preloads.first.complete(_plan);
    const replacement = PlaybackPlan(
      url: 'https://media.test/720.mp4',
      session: 'quality-720',
    );
    repository.preloads.last.complete(replacement);
    await tester.pump();
    expect(repository.releasedSessions, [_plan.session]);
    expect(
      await preloader.take(FixtureRepository.free, _episode, quality: 720),
      same(replacement),
    );
    preloader.dispose();
  });

  testWidgets('dispose cancels a waiting take without leaving its timeout', (
    tester,
  ) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    final taking = preloader.take(
      FixtureRepository.free,
      _episode,
      waitForPending: true,
    );
    preloader.dispose();
    await tester.pump();
    expect(await taking, isNull);
    repository.preloads.single.complete(_plan);
    await tester.pump();
    expect(repository.releasedSessions, [_plan.session]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired and failed preloads fall back instead of being opened', (
    tester,
  ) async {
    final repository = PreloadRepository();
    var now = DateTime(2026, 1, 1);
    final preloader = PlaybackPreloader(repository, now: () => now);
    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    repository.preloads.single.complete(_plan);
    await tester.pump();
    now = now.add(const Duration(minutes: 3));
    expect(await preloader.take(FixtureRepository.free, _episode), isNull);
    expect(repository.releasedSessions, [_plan.session]);

    preloader.prepare(FixtureRepository.free, _episode);
    await tester.pump(const Duration(milliseconds: 600));
    final taking = preloader.take(
      FixtureRepository.free,
      _episode,
      waitForPending: true,
    );
    repository.preloads.last.completeError(StateError('preload unavailable'));
    await tester.pump();
    expect(await taking, isNull);
    preloader.dispose();
    expect(tester.takeException(), isNull);
  });
}

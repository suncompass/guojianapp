import 'dart:async';

import 'package:duanju_app/models.dart';
import 'package:media_kit/media_kit.dart';

import 'fixtures.dart';

class ScriptedPlayer extends PlatformPlayer {
  ScriptedPlayer() : super(configuration: const PlayerConfiguration());
  final opened = <Media>[];
  final played = <bool>[];
  bool disposed = false;
  final rates = <double>[];
  int pauses = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final media = playable as Media;
    opened.add(media);
    played.add(play);
    final failed = media.uri.contains('broken');
    state = state.copyWith(
      position: failed ? Duration.zero : media.start ?? Duration.zero,
      duration: failed ? Duration.zero : const Duration(minutes: 2),
      playing: play,
      completed: false,
      buffering: false,
      width: failed ? 0 : 320,
      height: failed ? 0 : 180,
    );
    positionController.add(state.position);
    durationController.add(state.duration);
    playingController.add(play);
    if (failed) {
      fail();
    }
  }

  void fail() {
    errorController.add('synthetic network failure');
    errorController.add('synthetic decoder failure');
  }

  @override
  Future<void> stop() async {
    state = state.copyWith(
      position: Duration.zero,
      duration: Duration.zero,
      playing: false,
      buffering: false,
      width: 0,
      height: 0,
    );
    positionController.add(Duration.zero);
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration duration) async {
    state = state.copyWith(position: duration);
    positionController.add(duration);
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    state = state.copyWith(rate: rate);
    rateController.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    volumeController.add(volume);
  }

  void finishEpisode() {
    state = state.copyWith(
      position: state.duration,
      completed: true,
      playing: false,
    );
    positionController.add(state.position);
    completedController.add(true);
    playingController.add(false);
  }

  /// 片尾暂停先到，completed 尚未更新，不能提前假定两者原子同步。
  void emitEpisodeEndPause() {
    state = state.copyWith(
      position: state.duration,
      completed: false,
      playing: false,
    );
    playingController.add(false);
  }

  /// 补发完成事件，但保留滞后的状态快照，验证连播不依赖跨流更新顺序。
  void emitEpisodeCompleted() {
    completedController.add(true);
  }

  /// open 返回后解码器仍可能重置倍率并延迟报告暂停。
  void emitDecoderPause() {
    state = state.copyWith(playing: false, rate: 1);
    playingController.add(false);
  }

  /// 报告真正开播，用于验证延迟到达的开播通知会重新应用长按倍率。
  void emitPlaybackStarted() {
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  /// 补发滞后的暂停通知，但不改动当前状态快照。
  void emitStalePause() {
    playingController.add(false);
  }

  /// 报告缓冲进度，用于验证预加载不受缓冲事件影响。
  void emitBuffer(Duration value) {
    state = state.copyWith(buffer: value);
    bufferController.add(value);
  }

  void videoSize(int width, int height) {
    videoParamsController.add(
      VideoParams(w: width, h: height, dw: width, dh: height),
    );
  }

  void setBuffering(bool value) {
    state = state.copyWith(buffering: value);
    bufferingController.add(value);
  }

  @override
  Future<void> pause() async {
    pauses++;
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> playOrPause() async {
    state = state.copyWith(playing: !state.playing);
    playingController.add(state.playing);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class PreloadRepository extends RouteRepository {
  final preloads = <Completer<PlaybackPlan?>>[];
  final releasedSessions = <String>[];
  int preloadCancellations = 0;

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) {
    final pending = Completer<PlaybackPlan?>();
    preloads.add(pending);
    return pending.future;
  }

  @override
  Future<void> cancelPreload() async {
    preloadCancellations++;
  }

  @override
  Future<void> release(String session) async {
    releasedSessions.add(session);
    await super.release(session);
  }
}

class RouteRepository extends FixtureRepository {
  int primaryCalls = 0;
  int fallbackCalls = 0;
  final requestedQualities = <int>[];
  final requestedEpisodes = <int>[];
  bool broken = false;
  bool deferFallback = false;
  final active = <String>{};
  Completer<PlaybackPlan>? pending;

  PlaybackPlan plan(bool alternate) {
    final session = 'route-${primaryCalls + fallbackCalls}';
    active.add(session);
    return PlaybackPlan(
      url: 'https://media.test/${broken ? 'broken' : 'working'}-$session.mp4',
      session: session,
      routeIndex: alternate ? 1 : 0,
      routeCount: 2,
      quality: 1080,
      qualities: const [1080, 720],
    );
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    primaryCalls++;
    requestedQualities.add(quality);
    requestedEpisodes.add(episode.number);
    return plan(false);
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async {
    fallbackCalls++;
    if (deferFallback) {
      pending = Completer<PlaybackPlan>();
      return pending!.future;
    }
    return plan(true);
  }

  @override
  Future<void> release(String session) async {
    active.remove(session);
  }
}

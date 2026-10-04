import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/playback_phase.dart';

void main() {
  group('PlaybackPhaseMachine 迁移表', () {
    test('初始状态是 opening', () {
      expect(PlaybackPhaseMachine().phase, PlaybackPhase.opening);
    });

    test('opening 可以到达 ready / buffering / failed / closed', () {
      for (final next in [
        PlaybackPhase.ready,
        PlaybackPhase.buffering,
        PlaybackPhase.failed,
        PlaybackPhase.closed,
      ]) {
        final machine = PlaybackPhaseMachine();
        expect(machine.enter(next), isTrue, reason: 'opening -> $next');
        expect(machine.phase, next);
      }
    });

    test('ready 与 buffering 互相往返', () {
      final machine = PlaybackPhaseMachine()..enter(PlaybackPhase.ready);
      expect(machine.enter(PlaybackPhase.buffering), isTrue);
      expect(machine.enter(PlaybackPhase.ready), isTrue);
    });

    test('ready / buffering 可以重开下一集或失败或关闭', () {
      for (final from in [PlaybackPhase.ready, PlaybackPhase.buffering]) {
        for (final next in [
          PlaybackPhase.opening,
          PlaybackPhase.failed,
          PlaybackPhase.closed,
        ]) {
          final machine = PlaybackPhaseMachine()..enter(from);
          expect(machine.enter(next), isTrue, reason: '$from -> $next');
        }
      }
    });

    test('failed 只能重开或关闭', () {
      final machine = PlaybackPhaseMachine()..enter(PlaybackPhase.failed);
      expect(machine.enter(PlaybackPhase.ready), isFalse);
      expect(machine.enter(PlaybackPhase.buffering), isFalse);
      expect(machine.phase, PlaybackPhase.failed, reason: '拒绝后保持原状态');
      expect(machine.enter(PlaybackPhase.opening), isTrue);
    });

    test('closed 是终态，任何迁移都被拒绝', () {
      final machine = PlaybackPhaseMachine()..enter(PlaybackPhase.closed);
      for (final next in PlaybackPhase.values) {
        if (next == PlaybackPhase.closed) continue;
        expect(machine.enter(next), isFalse, reason: 'closed -> $next');
      }
      expect(machine.isTerminal, isTrue);
    });

    test('重复进入当前状态是幂等的', () {
      final machine = PlaybackPhaseMachine();
      expect(machine.enter(PlaybackPhase.opening), isTrue);
      expect(machine.enter(PlaybackPhase.opening), isTrue);
      machine.enter(PlaybackPhase.failed);
      expect(machine.enter(PlaybackPhase.failed), isTrue);
    });

    test('完整生命周期：opening -> ready -> buffering -> ready -> opening -> failed -> closed', () {
      final machine = PlaybackPhaseMachine();
      expect(machine.enter(PlaybackPhase.ready), isTrue);
      expect(machine.enter(PlaybackPhase.buffering), isTrue);
      expect(machine.enter(PlaybackPhase.ready), isTrue);
      expect(machine.enter(PlaybackPhase.opening), isTrue);
      expect(machine.enter(PlaybackPhase.failed), isTrue);
      expect(machine.enter(PlaybackPhase.closed), isTrue);
      expect(machine.isTerminal, isTrue);
    });

    test('拒绝迁移不改变状态', () {
      final machine = PlaybackPhaseMachine();
      expect(machine.enter(PlaybackPhase.opening), isTrue);
      expect(machine.enter(PlaybackPhase.failed), isTrue);
      expect(machine.enter(PlaybackPhase.buffering), isFalse);
      expect(machine.phase, PlaybackPhase.failed);
    });
  });
}

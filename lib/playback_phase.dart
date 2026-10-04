/// 播放器核心生命周期状态机（0.2.95）。
///
/// 把 `_PlayerScreenState` 中原先三个可以互相矛盾地散落的布尔
/// （`_loading` / `_buffering` / `_closed`，外加 `_error != null` 隐含的
/// 失败态）收敛为一个五态枚举，保证同一时刻只处于一个阶段：
///
/// - [PlaybackPhase.opening]：正在加载/换源/恢复一集（原 `_loading`）。
/// - [PlaybackPhase.ready]：已打开，正常播放或暂停（原 `!_loading` 且
///   未失败未关闭）。
/// - [PlaybackPhase.buffering]：ready 的子状态，正在缓冲（原 `_buffering`）。
/// - [PlaybackPhase.failed]：本次打开失败，`_error` 非空（原 `_error != null`）。
/// - [PlaybackPhase.closed]：屏幕已销毁，终态（原 `_closed`）。
///
/// 迁移只允许沿 [_transitions] 表进行；`enter` 返回是否成功，调用方在
/// 确定性迁移处断言成功，在事件驱动的迁移处（如缓冲流）允许静默忽略。
enum PlaybackPhase { opening, ready, buffering, failed, closed }

class PlaybackPhaseMachine {
  static const Map<PlaybackPhase, Set<PlaybackPhase>> _transitions = {
    // 打开中：成功、直接失败，或屏幕关闭。缓冲事件不在此阶段迁移
    // （完成时统一读取 player.state.buffering 落位）。
    PlaybackPhase.opening: {
      PlaybackPhase.ready,
      PlaybackPhase.buffering,
      PlaybackPhase.failed,
      PlaybackPhase.closed,
    },
    // 播放中：缓冲往返、失败后进入恢复、重开下一集、或关闭。
    PlaybackPhase.ready: {
      PlaybackPhase.buffering,
      PlaybackPhase.failed,
      PlaybackPhase.opening,
      PlaybackPhase.closed,
    },
    PlaybackPhase.buffering: {
      PlaybackPhase.ready,
      PlaybackPhase.failed,
      PlaybackPhase.opening,
      PlaybackPhase.closed,
    },
    // 失败：重试会先回到 opening，或直接关闭。
    PlaybackPhase.failed: {PlaybackPhase.opening, PlaybackPhase.closed},
    // 终态，不再迁移。
    PlaybackPhase.closed: {},
  };

  PlaybackPhase _current = PlaybackPhase.opening;

  PlaybackPhase get phase => _current;

  bool get isTerminal => _current == PlaybackPhase.closed;

  bool canEnter(PlaybackPhase next) =>
      next == _current || _transitions[_current]!.contains(next);

  /// 尝试迁移到 [next]，返回是否被状态机接受。
  ///
  /// 相同状态的重复进入视为幂等成功；被拒绝时保持原状态不变。
  bool enter(PlaybackPhase next) {
    if (!canEnter(next)) return false;
    _current = next;
    return true;
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'models.dart';
import 'remote_widgets.dart';

const episodePageSize = 50;

class EpisodeRangeBar extends StatelessWidget {
  const EpisodeRangeBar({
    super.key,
    required this.episodes,
    required this.page,
    required this.onLocate,
    this.currentNumber,
    this.title = '选集',
  });
  final List<Episode> episodes;
  final int page;
  final ValueChanged<int> onLocate;
  final int? currentNumber;
  final String title;

  Future<void> _jump(BuildContext context) async {
    final controller = TextEditingController();
    String? error;
    final index = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final number = int.tryParse(controller.text.trim());
            final found = episodes.indexWhere(
              (episode) => episode.number == number,
            );
            if (found < 0) {
              setState(() => error = '没有找到这一集，请输入已有集数');
            } else {
              Navigator.pop(context, found);
            }
          }

          return AlertDialog(
            title: const Text('跳转到指定集数'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: '集数', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(onPressed: submit, child: const Text('定位')),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (index != null && context.mounted) onLocate(index);
  }

  @override
  Widget build(BuildContext context) {
    final count = (episodes.length / episodePageSize).ceil();
    final current = episodes.indexWhere(
      (episode) => episode.number == currentNumber,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · ${episodes.length} 集',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (current >= 0)
                TextButton(
                  onPressed: () => onLocate(current),
                  child: const Text('定位当前'),
                ),
              IconButton(
                tooltip: '跳转集数',
                onPressed: episodes.isEmpty ? null : () => _jump(context),
                icon: const Icon(Icons.pin_outlined),
              ),
            ],
          ),
          if (count > 1)
            Row(
              children: [
                IconButton(
                  tooltip: '上一组选集',
                  onPressed: page > 0
                      ? () => onLocate((page - 1) * episodePageSize)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('episode-range'),
                      isExpanded: true,
                      value: page.clamp(0, count - 1),
                      items: [
                        for (var i = 0; i < count; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '第 ${episodes[i * episodePageSize].number}–${episodes[min((i + 1) * episodePageSize, episodes.length) - 1].number} 集',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onLocate(value * episodePageSize);
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一组选集',
                  onPressed: page + 1 < count
                      ? () => onLocate((page + 1) * episodePageSize)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class EpisodeBrowser extends StatefulWidget {
  const EpisodeBrowser({
    super.key,
    required this.episodes,
    required this.onSelected,
    this.currentNumber,
    this.selectedNumbers,
    this.keyPrefix = 'episode',
    this.title = '选集',
    this.compact = false,
    this.onExitUp,
    this.onExitDown,
  });
  final List<Episode> episodes;
  final ValueChanged<int> onSelected;
  final int? currentNumber;
  final Set<int>? selectedNumbers;
  final String keyPrefix;
  final String title;
  final bool compact;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;
  @override
  State<EpisodeBrowser> createState() => _EpisodeBrowserState();
}

class _EpisodeBrowserState extends State<EpisodeBrowser> {
  final _scroll = ScrollController();
  final _rangeScroll = ScrollController();
  final _indices = <int, int>{};
  List<String>? _remoteItemKeys;
  int _digits = 1;
  int _indexedLength = 0;
  String _layout = '';
  String _rangeLayout = '';
  int get _pageSize => episodePageSize;
  int _page = 0;
  int? _located;

  // 剧集列表由详情数据替换；只在数据变化时扫描，开关面板不再遍历全集。
  void _indexEpisodes() {
    _indices.clear();
    _digits = 1;
    _indexedLength = widget.episodes.length;
    _remoteItemKeys = null;
    for (var index = 0; index < widget.episodes.length; index++) {
      final number = widget.episodes[index].number;
      _indices.putIfAbsent(number, () => index);
      _digits = max(_digits, number.toString().length);
    }
    _layout = '';
    _rangeLayout = '';
  }

  @override
  void initState() {
    super.initState();
    _indexEpisodes();
    _page = (_indices[widget.currentNumber] ?? 0) ~/ _pageSize;
  }

  @override
  void didUpdateWidget(EpisodeBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        !identical(oldWidget.episodes, widget.episodes) ||
        _indexedLength != widget.episodes.length;
    if (changed) _indexEpisodes();
    if (changed || oldWidget.currentNumber != widget.currentNumber) {
      _page = (_indices[widget.currentNumber] ?? 0) ~/ _pageSize;
      _located = null;
    }
    _page = _page.clamp(0, max(0, (widget.episodes.length - 1) ~/ _pageSize));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _rangeScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _continuousGrid(context);
    final pageSize = _pageSize;
    _page = _page.clamp(0, max(0, (widget.episodes.length - 1) ~/ pageSize));
    final start = _page * pageSize;
    final visible = widget.episodes.skip(start).take(pageSize).toList();
    final television = AppLayout.isTelevision(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpisodeRangeBar(
          episodes: widget.episodes,
          page: _page,
          title: widget.title,
          currentNumber: widget.currentNumber,
          onLocate: (index) => setState(() {
            _page = index ~/ episodePageSize;
            _located = widget.episodes[index].number;
          }),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final digits = visible.fold<int>(
                1,
                (value, episode) =>
                    max(value, episode.number.toString().length),
              );
              final scale = MediaQuery.textScalerOf(context);
              final columns =
                  ((constraints.maxWidth - (widget.compact ? 8 : 36)) /
                          max(
                            widget.compact
                                ? 64
                                : television
                                ? 100
                                : 82,
                            scale.scale(widget.compact ? 18 : 20) *
                                    digits *
                                    .65 +
                                (widget.compact ? 28 : 40),
                          ))
                      .floor()
                      .clamp(widget.compact ? 4 : 1, 12);
              final extent = max(
                widget.compact ? 46.0 : 56.0,
                scale.scale(widget.compact ? 18 : 20) +
                    (widget.compact ? 24 : 30),
              );
              final target = max(
                0,
                visible.indexWhere(
                  (episode) =>
                      episode.number == (_located ?? widget.currentNumber),
                ),
              );
              final layout =
                  '$_page:$_located:${widget.currentNumber}:$columns:$extent:${constraints.maxHeight}';
              if (layout != _layout) {
                _layout = layout;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_scroll.hasClients || _layout != layout) {
                    return;
                  }
                  _scroll.jumpTo(
                    (18 +
                            target ~/ columns * (extent + 8) -
                            constraints.maxHeight / 2 +
                            extent / 2)
                        .clamp(0.0, _scroll.position.maxScrollExtent),
                  );
                });
              }
              return RemoteGrid(
                key: ValueKey('episode-page-$_page-$_located'),
                controller: _scroll,
                autofocus: television && _located != null,
                initialIndex: target,
                onExitUp: widget.onExitUp,
                onExitDown: widget.onExitDown,
                itemKeys: visible
                    .map((episode) => '${episode.number}')
                    .toList(),
                columns: columns,
                itemExtent: extent,
                spacing: widget.compact ? 6 : 8,
                padding: widget.compact
                    ? const EdgeInsets.fromLTRB(4, 4, 4, 12)
                    : const EdgeInsets.fromLTRB(18, 2, 18, 18),
                itemBuilder: (_, index, node, onFocus) {
                  final episode = visible[index];
                  return RemoteEpisodeButton(
                    key: ValueKey('${widget.keyPrefix}-${episode.number}'),
                    number: episode.number,
                    vip: episode.vip,
                    compact: widget.compact,
                    current:
                        widget.selectedNumbers?.contains(episode.number) ??
                        episode.number == widget.currentNumber,
                    focusNode: node,
                    onFocus: onFocus,
                    onPressed: () => widget.onSelected(start + index),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _locateCompact(int index) {
    setState(() {
      _located = widget.episodes[index].number;
      // 重复点击同一分组也应重新定位，而不是被布局缓存忽略。
      _layout = '';
    });
  }

  Widget _compactRangeSelector({required int target, required int pageCount}) {
    if (pageCount <= 1) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final selectedPage = (target ~/ episodePageSize).clamp(0, pageCount - 1);
    final itemWidth = max(
      88.0,
      MediaQuery.textScalerOf(context).scale(12) * (_digits * 2 + 1) * .65 + 26,
    );
    final layout =
        '$selectedPage:$itemWidth:$pageCount:${MediaQuery.sizeOf(context).width}';
    if (_rangeLayout != layout) {
      _rangeLayout = layout;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_rangeScroll.hasClients || _rangeLayout != layout) {
          return;
        }
        // 固定分组宽度，可直接定位后段分组，不构建前面的全部按钮。
        _rangeScroll.jumpTo(
          (4 +
                  selectedPage * itemWidth -
                  (_rangeScroll.position.viewportDimension - itemWidth) / 2)
              .clamp(0.0, _rangeScroll.position.maxScrollExtent),
        );
      });
    }
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              key: const ValueKey('compact-episode-ranges'),
              controller: _rangeScroll,
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
              scrollDirection: Axis.horizontal,
              itemExtent: itemWidth,
              itemCount: pageCount,
              itemBuilder: (context, page) {
                final start = page * episodePageSize;
                final end =
                    min(start + episodePageSize, widget.episodes.length) - 1;
                final selected = page == selectedPage;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: selected
                          ? colors.onPrimary
                          : colors.onSurface,
                      backgroundColor: selected
                          ? colors.primary
                          : Colors.transparent,
                      side: BorderSide(
                        color: selected
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    onPressed: () => _locateCompact(start),
                    child: Text(
                      '${widget.episodes[start].number}-${widget.episodes[end].number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '定位当前',
            onPressed: _indices.containsKey(widget.currentNumber)
                ? () => _locateCompact(_indices[widget.currentNumber]!)
                : null,
            icon: const Icon(Icons.my_location_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _compactEpisode(int index, {FocusNode? node, VoidCallback? onFocus}) {
    final episode = widget.episodes[index];
    return RemoteEpisodeButton(
      key: ValueKey('${widget.keyPrefix}-${episode.number}'),
      number: episode.number,
      vip: episode.vip,
      compact: true,
      current:
          widget.selectedNumbers?.contains(episode.number) ??
          episode.number == widget.currentNumber,
      focusNode: node,
      onFocus: onFocus,
      onPressed: () => widget.onSelected(index),
    );
  }

  Widget _continuousGrid(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final television = AppLayout.isTelevision(context);
      final scale = MediaQuery.textScalerOf(context);
      final minimum = max(40.0, scale.scale(14) * _digits * .62 + 22);
      final columns = ((constraints.maxWidth - 12) / minimum).floor().clamp(
        1,
        television ? 12 : 10,
      );
      final extent = max(34.0, scale.scale(14) + 18);
      final target = _indices[_located ?? widget.currentNumber] ?? 0;
      final pageCount = (widget.episodes.length / episodePageSize).ceil();
      final layout =
          'compact:${widget.episodes.length}:$_located:${widget.currentNumber}:$columns:$extent:${constraints.maxHeight}';
      if (layout != _layout) {
        _layout = layout;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients || _layout != layout) return;
          // 必须与网格的 padding、行间距一致，使用扣除分组栏后的实际视口。
          // 一像素的步长偏差也会在上千集时累积为几十行的定位误差。
          _scroll.jumpTo(
            (6 +
                    target ~/ columns * (extent + 5) -
                    (_scroll.position.viewportDimension - extent) / 2)
                .clamp(0.0, _scroll.position.maxScrollExtent),
          );
        });
      }
      return Column(
        children: [
          _compactRangeSelector(target: target, pageCount: pageCount),
          Expanded(
            // 手机只保留视口附近的按钮/焦点，不像遥控网格那样累计已访问节点。
            // 电视保留原有方向键导航，避免触屏优化改变遥控行为。
            child: television
                ? RemoteGrid(
                    key: ValueKey('episode-continuous-$_located'),
                    controller: _scroll,
                    autofocus: _located != null,
                    initialIndex: target,
                    itemKeys: _remoteItemKeys ??= widget.episodes
                        .map((episode) => '${episode.number}')
                        .toList(),
                    columns: columns,
                    itemExtent: extent,
                    spacing: 5,
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                    itemBuilder: (_, index, node, onFocus) =>
                        _compactEpisode(index, node: node, onFocus: onFocus),
                  )
                : GridView.builder(
                    key: const ValueKey('compact-episode-grid'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                    cacheExtent: extent + 5,
                    addAutomaticKeepAlives: false,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: extent,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (_, index) => _compactEpisode(index),
                  ),
          ),
        ],
      );
    },
  );
}

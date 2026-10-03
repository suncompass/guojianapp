import 'dart:async';

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'catalog_filters.dart';
import 'core_bridge.dart';
import 'drama_actions.dart';
import 'local_store.dart';
import 'playback_launch_screen.dart';
import 'recommendation_models.dart';
import 'recommendation_service.dart';
import 'remote_widgets.dart';
import 'widgets.dart';

/// 底部「动态」：所有用户看过的短剧自动汇总成的推荐榜单，可按站源和分类筛选。
class FeedsScreen extends StatefulWidget {
  const FeedsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = true,
    this.onExitLeft,
  });

  final AppRepository repository;
  final LocalStore store;
  final bool embedded;
  final VoidCallback? onExitLeft;

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  final _sourceKey = GlobalKey<RemoteRowState>();
  final _categoryKey = GlobalKey<RemoteRowState>();
  final _gridKey = GlobalKey<RemoteGridState>();
  bool _busy = false;

  RecommendationService? get _service => RecommendationService.current;

  Future<void> _refresh() async {
    final service = _service;
    if (service == null || _busy) return;
    setState(() => _busy = true);
    await service.refresh();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(FeedItem item) async {
    await openPlaybackDirectly(
      context,
      drama: item.drama,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _actions(FeedItem item) async {
    final service = _service;
    if (service == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('播放'),
              onTap: () => Navigator.pop(context, 'play'),
            ),
            if (service.myCount > 0)
              ListTile(
                key: const ValueKey('feed-manage-mine'),
                leading: const Icon(Icons.library_add_check_rounded),
                title: const Text('管理我发布的记录'),
                subtitle: const Text('可多选删除'),
                onTap: () => Navigator.pop(context, 'manage'),
              ),
            if (item.mine)
              ListTile(
                key: const ValueKey('feed-remove-mine'),
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('删除我发布的记录'),
                subtitle: const Text('从动态中撤下，之后再看到有效观看才会重新出现'),
                onTap: () => Navigator.pop(context, 'remove'),
              )
            else ...[
              ListTile(
                key: const ValueKey('feed-hide-item'),
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('不看这条'),
                subtitle: const Text('只影响本机显示'),
                onTap: () => Navigator.pop(context, 'hide'),
              ),
              if (_blockCandidates(item, service).isNotEmpty)
                ListTile(
                  key: const ValueKey('feed-block-publisher'),
                  leading: const Icon(Icons.block_rounded),
                  title: const Text('屏蔽发布者'),
                  subtitle: const Text('本机不再显示该发布者的全部动态'),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
            ],
            if (service.hiddenCount > 0 || service.blockedCount > 0)
              ListTile(
                key: const ValueKey('feed-restore-hidden'),
                leading: const Icon(Icons.settings_backup_restore_rounded),
                title: const Text('恢复隐藏与屏蔽'),
                subtitle: Text(
                  '已隐藏 ${service.hiddenCount} 条 · 已屏蔽 ${service.blockedCount} 个发布者',
                ),
                onTap: () => Navigator.pop(context, 'restore'),
              ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('刷新动态'),
              onTap: () => Navigator.pop(context, 'refresh'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      await _open(item);
    } else if (action == 'manage') {
      await _manageMine();
    } else if (action == 'remove') {
      await service.remove(item.id);
      if (mounted) _toast('已删除自己发布的记录');
    } else if (action == 'hide') {
      await service.hide(item.id);
      if (mounted) _toast('已隐藏，可在菜单里恢复');
    } else if (action == 'block') {
      await _blockPublisher(item);
    } else if (action == 'restore') {
      await service.restoreHidden();
      await service.restoreBlocked();
      if (mounted) _toast('已恢复隐藏与屏蔽');
    } else if (action == 'refresh') {
      await _refresh();
    }
  }

  /// 我发布的记录：多选删除，避免只能逐条删除或一次性全部清空。
  Future<void> _manageMine() async {
    final service = _service;
    if (service == null) return;
    final entries = service.myEntries;
    if (entries.isEmpty) {
      if (mounted) _toast('你还没有发布过记录');
      return;
    }
    final selected = <String>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final all = selected.length == entries.length;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('我发布的记录 ${entries.length} 部'),
                    subtitle: const Text('勾选后删除，未勾选的会继续保留在榜单里'),
                    trailing: TextButton(
                      key: const ValueKey('feed-manage-toggle-all'),
                      onPressed: () => setSheetState(() {
                        if (all) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(entries.map((entry) => entry.id));
                        }
                      }),
                      child: Text(all ? '取消全选' : '全选'),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return CheckboxListTile(
                          key: ValueKey('feed-manage-${entry.id}'),
                          dense: true,
                          value: selected.contains(entry.id),
                          title: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.category.isEmpty
                                ? entry.source
                                : '${entry.source} · ${entry.category}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) => setSheetState(() {
                            if (value ?? false) {
                              selected.add(entry.id);
                            } else {
                              selected.remove(entry.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('feed-manage-delete'),
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(context, true),
                            child: Text('删除所选 ${selected.length} 部'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (confirmed != true || selected.isEmpty || !mounted) return;
    await service.removeMany(selected);
    if (mounted) _toast('已删除 ${selected.length} 部我发布的记录');
  }

  List<String> _blockCandidates(FeedItem item, RecommendationService service) {    final candidates =
        [
          for (final pubkey in item.publishers)
            if (pubkey != service.publicKey && !service.blockedPublisher(pubkey))
              pubkey,
        ]..sort();
    return candidates;
  }

  Future<void> _blockPublisher(FeedItem item) async {
    final service = _service;
    if (service == null) return;
    final candidates = _blockCandidates(item, service);
    if (candidates.isEmpty) return;
    var chosen = candidates.first;
    if (candidates.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                dense: true,
                title: Text('选择要屏蔽的发布者'),
              ),
              for (final pubkey in candidates)
                ListTile(
                  key: ValueKey('block-$pubkey'),
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text('${pubkey.substring(0, 8)}…'),
                  onTap: () => Navigator.pop(context, pubkey),
                ),
            ],
          ),
        ),
      );
      if (!mounted || picked == null) return;
      chosen = picked;
    }
    await service.blockPublisher(chosen);
    if (mounted) _toast('已屏蔽该发布者');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return const StatusPanel(
        title: '动态尚未就绪',
        message: '重新打开应用后会自动连接推荐动态。',
      );
    }
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!service.attached) {
          return const Center(child: CircularProgressIndicator());
        }
        final television = AppLayout.isTelevision(context);
        final items = service.items;
        return Column(
          children: [
            CatalogFilters(
              key: const ValueKey('feed-source-filters'),
              categories: service.sourceChoices,
              category: service.sourceFocus,
              selected: service.selectedSources,
              remoteKey: _sourceKey,
              remoteAutofocus: television,
              onCategory: service.toggleSource,
              onRetry: _refresh,
              onExitDown: television
                  ? () => _categoryKey.currentState?.focusCurrent()
                  : null,
            ),
            CatalogFilters(
              key: const ValueKey('feed-category-filters'),
              categories: service.categoryFilters,
              category: service.categoryFilter,
              remoteKey: _categoryKey,
              onCategory: service.setCategoryFilter,
              onRetry: _refresh,
              onExitUp: television
                  ? () => _sourceKey.currentState?.focusCurrent()
                  : null,
              onExitDown: television
                  ? () => _gridKey.currentState?.focusCurrent()
                  : null,
            ),
            if (service.notice.isNotEmpty) _noticeBar(service),
            Expanded(
              child: _grid(service, items, television),
            ),
          ],
        );
      },
    );
  }

  Widget _noticeBar(RecommendationService service) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(service.notice, style: theme.textTheme.bodySmall),
          ),
          IconButton(
            tooltip: '知道了',
            onPressed: service.clearNotice,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    RecommendationService service,
    List<FeedItem> items,
    bool television,
  ) {
    if (items.isEmpty) {
      final sourceFiltered = service.allItems.isNotEmpty;
      return StatusPanel(
        title: sourceFiltered ? '这个筛选下还没有动态' : '还没有人推荐短剧',
        message: sourceFiltered
            ? '换一个站源或分类试试。'
            : '看满 ${recommendationMinWatchMs ~/ 60000} 分钟或连着看完 '
                  '$recommendationMinEpisodes 集，看过的短剧会自动出现在这里。',
        onRetry: _busy ? null : _refresh,
        action: '刷新动态',
        icon: Icons.play_circle_outline_rounded,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        if (television) {
          final columns = ((constraints.maxWidth - 36) / 150).floor().clamp(
            1,
            8,
          );
          final tileWidth =
              (constraints.maxWidth - 36 - (columns - 1) * 14) / columns;
          return RemoteGrid(
            key: _gridKey,
            itemKeys: [for (final item in items) item.id],
            columns: columns,
            itemExtent: DramaTile.extentFor(context, tileWidth - 14) + 14,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
            onExitUp: () => _categoryKey.currentState?.focusCurrent(),
            onExitLeft: widget.onExitLeft,
            itemBuilder: (_, index, node, onFocus) {
              final item = items[index];
              return _tile(item, focusNode: node, onFocus: onFocus);
            },
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 0, padding, 24),
                sliver: SliverGrid(
                  gridDelegate: dramaGridDelegate(
                    context,
                    constraints.maxWidth - 2 * padding,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => _tile(items[index]),
                    childCount: items.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(FeedItem item, {FocusNode? focusNode, VoidCallback? onFocus}) {
    final drama = item.drama;
    return DramaTile(
      key: ValueKey('feed-${item.id}'),
      drama: drama,
      repository: widget.repository,
      focusNode: focusNode,
      onFocus: onFocus,
      subtitle: item.sourceName,
      countBadge: item.recommendLabel,
      countBadgeHighlight: item.mine,
      onTap: () => unawaited(_open(item)),
      onLongPress: () => unawaited(_actions(item)),
      onMore: () => unawaited(_actions(item)),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => unawaited(_actions(item)),
      ),
    );
  }
}

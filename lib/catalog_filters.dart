import 'dart:math';

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'models.dart';
import 'remote_widgets.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.categories,
    this.category = '',
    this.selected,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.trailing,
    this.remoteKey,
    this.remoteAutofocus = false,
    this.onExitUp,
    this.onExitDown,
  });

  final List<CatalogCategory> categories;
  final String category;
  final Set<String>? selected;
  final String? error;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final Widget? trailing;
  final GlobalKey<RemoteRowState>? remoteKey;
  final bool remoteAutofocus;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _anchors = <String, GlobalKey>{};

  bool _isSelected(String id) =>
      widget.selected?.contains(id) ?? id == widget.category;

  int get _selectedIndex {
    final index = widget.categories.indexWhere(
      (entry) => entry.id == widget.category,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant CatalogFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anchor = _anchors[widget.category]?.currentContext;
        if (mounted && anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            alignment: .4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    return SizedBox(
      height: television
          ? 64
          : max(52, MediaQuery.textScalerOf(context).scale(14) + 28),
      child: Row(
        children: [
          Expanded(
            child: television
                ? RemoteRow(
                    key: widget.remoteKey,
                    itemKeys: [for (final entry in widget.categories) entry.id],
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    initialIndex: _selectedIndex,
                    autofocus: widget.remoteAutofocus,
                    onExitUp: widget.onExitUp,
                    onExitDown: widget.onExitDown,
                    itemBuilder: (_, index, node, onFocus) {
                      final entry = widget.categories[index];
                      return KeyedSubtree(
                        key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                        child: RemoteButton(
                          key: ValueKey('category-${entry.id}'),
                          label: entry.name,
                          selected: _isSelected(entry.id),
                          focusNode: node,
                          onFocus: onFocus,
                          onPressed: () => widget.onCategory(entry.id),
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    key: const ValueKey('catalog-categories'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final entry in widget.categories)
                          Padding(
                            key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              key: ValueKey('category-${entry.id}'),
                              label: Text(entry.name),
                              selected: _isSelected(entry.id),
                              showCheckmark: false,
                              onSelected: (_) => widget.onCategory(entry.id),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (widget.error != null)
            IconButton(
              tooltip: widget.error,
              onPressed: widget.onRetry,
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

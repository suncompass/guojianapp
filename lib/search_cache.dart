import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SearchCacheEntry {
  SearchCacheEntry({
    required this.source,
    required this.query,
    required this.items,
    required this.total,
    this.hasMore = false,
    this.warning = '',
    DateTime? storedAt,
  }) : storedAt = storedAt ?? DateTime.now();

  final String source;
  final String query;
  final List<Drama> items;
  final int total;
  final bool hasMore;
  final String warning;
  final DateTime storedAt;

  bool get complete => !hasMore && items.length >= total;
  bool get fresh => DateTime.now().difference(storedAt) < SearchResultCache.ttl;

  factory SearchCacheEntry.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String? ?? '';
    final query = json['query'] as String? ?? '';
    final rows = json['items'] as List? ?? const [];
    final storedAt = DateTime.tryParse(json['storedAt']?.toString() ?? '');
    if (source.trim().isEmpty ||
        query.trim().isEmpty ||
        storedAt == null ||
        rows.any((row) => row is! Map)) {
      throw const FormatException('搜索缓存条目无效');
    }
    return SearchCacheEntry(
      source: source,
      query: query,
      items: [
        for (final row in rows)
          Drama.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      total: intValue(json['total']),
      hasMore: json['hasMore'] == true,
      warning: json['warning'] as String? ?? '',
      storedAt: storedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'query': query,
    'items': [for (final item in items) item.toJson()],
    'total': total,
    'hasMore': hasMore,
    'warning': warning,
    'storedAt': storedAt.toIso8601String(),
  };
}

class SearchResultCache {
  SearchResultCache._();

  static final SearchResultCache instance = SearchResultCache._();

  static const _limit = 24;
  static const ttl = Duration(minutes: 20);
  static const _storageKey = 'searchResultCache.v1';

  final Map<String, SearchCacheEntry> _entries = {};
  final Map<String, Future<SearchCacheEntry>> _pending = {};
  SharedPreferences? _preferences;
  Future<void> _persisting = Future<void>.value();

  Future<void> initialize(SharedPreferences preferences) async {
    _preferences = preferences;
    _entries.clear();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final rows = decoded is Map ? decoded['entries'] : null;
      if (rows is! List) return;
      for (final row in rows) {
        if (row is! Map) continue;
        try {
          final entry = SearchCacheEntry.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (entry.items.isEmpty && entry.warning.isNotEmpty) continue;
          _entries[_key(entry.source, entry.query)] = entry;
          if (_entries.length >= _limit) break;
        } catch (_) {}
      }
    } catch (_) {
      _entries.clear();
    }
  }

  Future<void> flush() => _persisting;

  void _schedulePersist() {
    final preferences = _preferences;
    if (preferences == null) return;
    final payload = jsonEncode({
      'version': 1,
      'entries': [for (final entry in _entries.values) entry.toJson()],
    });
    _persisting = _persisting.then((_) async {
      try {
        await preferences.setString(_storageKey, payload);
      } catch (_) {}
    });
  }

  String _key(String source, String query) =>
      '${source.trim()}|${_normalize(query)}';

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  SearchCacheEntry? read(
    String source,
    String query, {
    bool allowStale = false,
  }) {
    final entry = _entries[_key(source, query)];
    if (entry == null || !allowStale && !entry.fresh) return null;
    return entry;
  }

  SearchCacheEntry? readAnyQuery(
    String source, {
    bool allowStale = false,
    bool Function(SearchCacheEntry)? where,
  }) {
    SearchCacheEntry? newest;
    for (final entry in _entries.values) {
      if (entry.source.trim() != source.trim()) continue;
      if (!allowStale && !entry.fresh) continue;
      if (where != null && !where(entry)) continue;
      if (newest == null || entry.storedAt.isAfter(newest.storedAt)) {
        newest = entry;
      }
    }
    return newest;
  }

  void write(SearchCacheEntry entry) {
    if (entry.items.isEmpty && entry.warning.isNotEmpty) return;
    final key = _key(entry.source, entry.query);
    final existing = _entries[key];
    if (existing != null) {
      if (existing.storedAt.isAfter(entry.storedAt)) return;
      if (entry.warning.isNotEmpty &&
          existing.items.length >= entry.items.length) {
        return;
      }
      if (existing.fresh &&
          existing.complete &&
          !entry.complete &&
          existing.items.length >= entry.items.length) {
        return;
      }
    }
    if (_entries.length >= _limit && !_entries.containsKey(key)) {
      final oldest = _entries.entries.reduce(
        (left, right) =>
            left.value.storedAt.isBefore(right.value.storedAt) ? left : right,
      );
      _entries.remove(oldest.key);
    }
    _entries[key] = entry;
    _schedulePersist();
  }

  void writeItems({
    required String source,
    required String query,
    required List<Drama> items,
    int total = 0,
    bool hasMore = false,
    String warning = '',
  }) => write(
    SearchCacheEntry(
      source: source,
      query: query,
      items: List<Drama>.unmodifiable(items),
      total: total <= 0 ? items.length : total,
      hasMore: hasMore,
      warning: warning,
    ),
  );

  Future<SearchCacheEntry> coalesce(
    String source,
    String query,
    Future<SearchCacheEntry> Function() load,
  ) {
    final key = _key(source, query);
    final pending = _pending[key];
    if (pending != null) return pending;
    late final Future<SearchCacheEntry> future;
    future = Future<SearchCacheEntry>.sync(load).whenComplete(() {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  void clear() {
    _entries.clear();
    _pending.clear();
    _schedulePersist();
  }
}

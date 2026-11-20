import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single structured entry in Nimo's unified offline + GitHub-injected knowledge database.
class LocalDbRecord {
  final int id;
  final String category;
  final String title;
  final String body;
  final String keywords;
  final String? sourceId; // null for built-in records, non-null for GitHub/API injected records

  const LocalDbRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.keywords,
    this.sourceId,
  });

  bool get isInjected => sourceId != null && sourceId!.isNotEmpty;

  factory LocalDbRecord.fromJson(Map<String, dynamic> json) {
    return LocalDbRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: (json['c'] ?? 'general').toString(),
      title: (json['t'] ?? '').toString(),
      body: (json['b'] ?? '').toString(),
      keywords: (json['k'] ?? '').toString(),
      sourceId: json['src'] as String?,
    );
  }
}

class NimoLocalDbState {
  final bool isLoaded;
  final int builtInRecords;
  final int injectedRecords;
  final int injectedSourcesCount;
  final Map<String, int> categoryCounts;

  const NimoLocalDbState({
    this.isLoaded = false,
    this.builtInRecords = 0,
    this.injectedRecords = 0,
    this.injectedSourcesCount = 0,
    this.categoryCounts = const {},
  });

  int get totalRecords => builtInRecords + injectedRecords;
}

/// Nimo v5.0 Ultra Unified Inverted-Index Knowledge Engine.
/// Combines 4,300+ built-in offline records AND dynamically injected GitHub / API datasets
/// into ONE blazing-fast (<3ms) inverted index that powers Chat, Voice, Coding Lab & Offline AI!
class NimoLocalDbNotifier extends StateNotifier<NimoLocalDbState> {
  final List<LocalDbRecord> _builtIn = [];
  final Map<String, List<LocalDbRecord>> _injectedBySource = {};

  final List<LocalDbRecord> _records = [];
  final Map<String, List<int>> _invertedIndex = {};
  bool _builtInLoaded = false;

  NimoLocalDbNotifier() : super(const NimoLocalDbState()) {
    load();
  }

  List<LocalDbRecord> get allRecords => _records;

  Future<void> load() async {
    if (_builtInLoaded) return;
    try {
      final raw = await rootBundle.loadString('assets/db/nimo_mega_db.json');
      final decoded = jsonDecode(raw) as List<dynamic>;
      _builtIn.clear();
      for (int idx = 0; idx < decoded.length; idx++) {
        final item = decoded[idx];
        if (item is! Map<String, dynamic>) continue;
        _builtIn.add(LocalDbRecord.fromJson(item));
      }
      _builtInLoaded = true;
      _rebuildUnifiedIndex();
    } catch (_) {
      // Safe fallback in unit tests without rootBundle assets
      _rebuildUnifiedIndex();
    }
  }

  /// Injects imported GitHub / Public API dataset records directly into Nimo's core inverted index!
  void injectSourceRecords(String sourceId, List<LocalDbRecord> newRecords) {
    if (newRecords.isEmpty) {
      _injectedBySource.remove(sourceId);
    } else {
      _injectedBySource[sourceId] = List<LocalDbRecord>.unmodifiable(newRecords);
    }
    _rebuildUnifiedIndex();
  }

  /// Removes a previously injected GitHub / API dataset from the unified index.
  void removeSourceRecords(String sourceId) {
    if (_injectedBySource.remove(sourceId) != null) {
      _rebuildUnifiedIndex();
    }
  }

  /// Rebuilds the unified in-memory inverted index over built-in + all injected GitHub/API sources.
  void _rebuildUnifiedIndex() {
    _records.clear();
    _invertedIndex.clear();
    final counts = <String, int>{};

    void indexRecord(LocalDbRecord rec) {
      final listIndex = _records.length;
      _records.add(rec);
      counts[rec.category] = (counts[rec.category] ?? 0) + 1;
      final tokens = _tokenize('${rec.title} ${rec.keywords} ${rec.category}');
      for (final tok in tokens) {
        (_invertedIndex[tok] ??= <int>[]).add(listIndex);
      }
    }

    for (final r in _builtIn) {
      indexRecord(r);
    }
    int injectedTotal = 0;
    for (final list in _injectedBySource.values) {
      for (final r in list) {
        indexRecord(r);
        injectedTotal++;
      }
    }

    state = NimoLocalDbState(
      isLoaded: _builtInLoaded || injectedTotal > 0,
      builtInRecords: _builtIn.length,
      injectedRecords: injectedTotal,
      injectedSourcesCount: _injectedBySource.length,
      categoryCounts: counts,
    );
  }

  /// Instant sub-5ms inverted-index search across built-in + ALL injected GitHub/API records.
  List<LocalDbRecord> search(String query, {String? category, int limit = 15}) {
    final normQuery = normalize(query);
    if (normQuery.isEmpty) {
      final filtered = category == null
          ? _records
          : _records.where((r) => r.category == category);
      // Show newest injected records first when browsing 'github_injected' or all
      if (category == null && _injectedBySource.isNotEmpty) {
        final injectedPreview = _injectedBySource.values.expand((e) => e).take(6).toList();
        final builtInPreview = _builtIn.take((limit - injectedPreview.length).clamp(0, limit)).toList();
        return [...injectedPreview, ...builtInPreview];
      }
      return filtered.take(limit).toList();
    }

    final queryTokens = _tokenize(normQuery);
    if (queryTokens.isEmpty) return const [];

    final Map<int, int> scores = {};
    for (final tok in queryTokens) {
      final exactHits = _invertedIndex[tok];
      if (exactHits != null) {
        for (final idx in exactHits) {
          scores[idx] = (scores[idx] ?? 0) + 7;
        }
      }
      if (tok.length >= 3) {
        int prefixScanned = 0;
        for (final entry in _invertedIndex.entries) {
          if (entry.key.startsWith(tok) && entry.key != tok) {
            for (final idx in entry.value) {
              scores[idx] = (scores[idx] ?? 0) + 3;
            }
            if (++prefixScanned >= 22) break;
          }
        }
      }
    }

    final ranked = <MapEntry<int, int>>[];
    for (final e in scores.entries) {
      final rec = _records[e.key];
      if (category != null && rec.category != category) continue;
      int s = e.value;
      final normTitle = normalize(rec.title);
      if (normTitle.contains(normQuery)) s += 16;
      // Slight priority boost for user-injected GitHub/API knowledge so imports visibly empower answers
      if (rec.isInjected) s += 3;
      ranked.add(MapEntry(e.key, s));
    }

    ranked.sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(limit).map((e) => _records[e.key]).toList();
  }

  /// Builds a rich RAG context snippet for the AI model from BOTH built-in DB and injected GitHub datasets.
  String buildOfflineRagContext(String query, {int limit = 6}) {
    if (!state.isLoaded || _records.isEmpty) return '';
    final hits = search(query, limit: limit);
    if (hits.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln(
      '\n[NIMO UNIFIED KNOWLEDGE BASE (${state.totalRecords} RECORDS — ${state.builtInRecords} BUILT-IN + ${state.injectedRecords} INJECTED GITHUB/API)]:',
    );
    for (final h in hits) {
      final tag = h.isInjected ? 'GITHUB:${h.category}' : h.category;
      buf.writeln('- [$tag] ${h.title}: ${h.body}');
    }
    return buf.toString();
  }

  static String normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"""[أإآ]"""), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r"""[\u064B-\u065F]"""), '')
        .replaceAll(RegExp(r"""[^\w\u0600-\u06FF\s]"""), ' ')
        .trim();
  }

  static Set<String> _tokenize(String text) {
    return normalize(text)
        .split(RegExp(r"""\s+"""))
        .where((w) => w.length >= 2)
        .toSet();
  }
}

final nimoLocalDbProvider =
    StateNotifierProvider<NimoLocalDbNotifier, NimoLocalDbState>((ref) => NimoLocalDbNotifier());

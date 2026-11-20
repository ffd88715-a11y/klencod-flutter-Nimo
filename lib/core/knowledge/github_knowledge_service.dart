import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';

/// Represents a curated or custom GitHub / Public API knowledge dataset.
class GithubDatasetSource {
  final String id;
  final String titleAr;
  final String titleEn;
  final String category;
  final String repoSlug;
  final String rawUrl;
  final String format; // 'csv' | 'json' | 'md' | 'txt' | 'jsonl' | 'auto'
  final String descriptionAr;
  final String descriptionEn;
  final bool isCustom;
  final bool isApiRepo;

  const GithubDatasetSource({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.category,
    required this.repoSlug,
    required this.rawUrl,
    required this.format,
    required this.descriptionAr,
    required this.descriptionEn,
    this.isCustom = false,
    this.isApiRepo = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'category': category,
        'repoSlug': repoSlug,
        'rawUrl': rawUrl,
        'format': format,
        'descriptionAr': descriptionAr,
        'descriptionEn': descriptionEn,
        'isCustom': isCustom,
        'isApiRepo': isApiRepo,
      };

  factory GithubDatasetSource.fromJson(Map<String, dynamic> json) {
    return GithubDatasetSource(
      id: (json['id'] ?? '').toString(),
      titleAr: (json['titleAr'] ?? '').toString(),
      titleEn: (json['titleEn'] ?? '').toString(),
      category: (json['category'] ?? 'Custom').toString(),
      repoSlug: (json['repoSlug'] ?? 'github').toString(),
      rawUrl: (json['rawUrl'] ?? '').toString(),
      format: (json['format'] ?? 'auto').toString(),
      descriptionAr: (json['descriptionAr'] ?? '').toString(),
      descriptionEn: (json['descriptionEn'] ?? '').toString(),
      isCustom: json['isCustom'] == true,
      isApiRepo: json['isApiRepo'] == true,
    );
  }
}

/// A single indexed knowledge chunk pulled from GitHub or a Live API and injected into Nimo DB.
class KnowledgeEntry {
  final String sourceId;
  final String sourceTitle;
  final String title;
  final String content;

  const KnowledgeEntry({
    required this.sourceId,
    required this.sourceTitle,
    required this.title,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        's': sourceId,
        'st': sourceTitle,
        't': title,
        'c': content,
      };

  factory KnowledgeEntry.fromJson(Map<String, dynamic> json) {
    return KnowledgeEntry(
      sourceId: (json['s'] ?? '').toString(),
      sourceTitle: (json['st'] ?? '').toString(),
      title: (json['t'] ?? '').toString(),
      content: (json['c'] ?? '').toString(),
    );
  }
}

class GithubKnowledgeState {
  final List<GithubDatasetSource> sources;
  final Map<String, List<KnowledgeEntry>> entriesBySource;
  final Map<String, DateTime> lastSyncedBySource;
  final Set<String> syncingIds;
  final bool ragEnabled;
  final String? lastError;
  final String? lastSuccessBanner;

  const GithubKnowledgeState({
    this.sources = const [],
    this.entriesBySource = const {},
    this.lastSyncedBySource = const {},
    this.syncingIds = const {},
    this.ragEnabled = true,
    this.lastError,
    this.lastSuccessBanner,
  });

  int get totalEntries =>
      entriesBySource.values.fold<int>(0, (sum, list) => sum + list.length);

  int get syncedSourcesCount =>
      entriesBySource.values.where((list) => list.isNotEmpty).length;

  GithubKnowledgeState copyWith({
    List<GithubDatasetSource>? sources,
    Map<String, List<KnowledgeEntry>>? entriesBySource,
    Map<String, DateTime>? lastSyncedBySource,
    Set<String>? syncingIds,
    bool? ragEnabled,
    String? lastError,
    String? lastSuccessBanner,
    bool clearError = false,
    bool clearBanner = false,
  }) {
    return GithubKnowledgeState(
      sources: sources ?? this.sources,
      entriesBySource: entriesBySource ?? this.entriesBySource,
      lastSyncedBySource: lastSyncedBySource ?? this.lastSyncedBySource,
      syncingIds: syncingIds ?? this.syncingIds,
      ragEnabled: ragEnabled ?? this.ragEnabled,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastSuccessBanner: clearBanner ? null : (lastSuccessBanner ?? this.lastSuccessBanner),
    );
  }
}

/// Nimo v5.0 Ultra — GitHub & Public API Mega-Knowledge Ingestion & Core DB Injector.
/// Every synced dataset is immediately parsed, cached locally, AND injected into `NimoLocalDbNotifier`
/// so all 16+ GitHub/API repositories supercharge AI Chat, Live Voice, Coding Lab & Offline Search!
class GithubKnowledgeNotifier extends StateNotifier<GithubKnowledgeState> {
  static const _kEntriesPrefix = 'lisora_gh_entries_v3_';
  static const _kMetaKey = 'lisora_gh_meta_v3';
  static const _kCustomSourcesKey = 'lisora_gh_custom_sources_v3';
  static const _kRagEnabledKey = 'lisora_gh_rag_enabled_v3';

  static const List<GithubDatasetSource> builtInSources = [
    // --- PUBLIC API REPOSITORIES & LIVE ENDPOINTS ---
    GithubDatasetSource(
      id: 'public_apis',
      titleAr: 'دليل الـ APIs العالمية المجانية (+1400 API)',
      titleEn: 'Public APIs Mega Directory (1400+ APIs)',
      category: 'APIs',
      repoSlug: 'public-apis/public-apis',
      rawUrl: 'https://raw.githubusercontent.com/public-apis/public-apis/master/README.md',
      format: 'md',
      isApiRepo: true,
      descriptionAr: 'أكبر مستودع على GitHub للواجهات البرمجية المجانية في الذكاء والطقس والمال والأخبار والبرمجة.',
      descriptionEn: 'Largest GitHub directory of free public APIs across all categories.',
    ),
    GithubDatasetSource(
      id: 'public_apis_json',
      titleAr: 'قاعدة بيانات Public APIs المهيكلة (JSON)',
      titleEn: 'Structured Public APIs JSON Corpus',
      category: 'APIs',
      repoSlug: 'marcelscruz/public-apis',
      rawUrl: 'https://raw.githubusercontent.com/marcelscruz/public-apis/main/db/resources.json',
      format: 'json',
      isApiRepo: true,
      descriptionAr: 'بيانات JSON منظمة لمئات الـ APIs المجانية بروابطها وتصنيفاتها المباشرة للربط الفوري.',
      descriptionEn: 'Clean structured JSON database of hundreds of free public APIs with direct URLs.',
    ),
    GithubDatasetSource(
      id: 'free_for_dev',
      titleAr: 'موسوعة خدمات السحابة والـ APIs المجانية للمطورين',
      titleEn: 'Free-For-Dev Cloud & API Services',
      category: 'APIs',
      repoSlug: 'ripienaar/free-for-dev',
      rawUrl: 'https://raw.githubusercontent.com/ripienaar/free-for-dev/master/README.md',
      format: 'md',
      isApiRepo: true,
      descriptionAr: 'مئات خدمات الاستضافة وقواعد البيانات والـ APIs المجانية لمشاريع المطورين.',
      descriptionEn: 'Massive curated list of free-tier cloud, database, hosting, and API services.',
    ),
    GithubDatasetSource(
      id: 'apis_guru_live',
      titleAr: 'مستودع OpenAPI العالمي الحي (APIs.guru)',
      titleEn: 'APIs.guru Live OpenAPI Directory',
      category: 'APIs',
      repoSlug: 'APIs-guru/openapi-directory',
      rawUrl: 'https://api.apis.guru/v2/list.json',
      format: 'json',
      isApiRepo: true,
      descriptionAr: 'اتصال مباشر بواجهة APIs.guru الرسمية لجلب فهرس واجهات OpenAPI العالمية.',
      descriptionEn: 'Live connection to APIs.guru official OpenAPI specifications index.',
    ),
    GithubDatasetSource(
      id: 'rest_countries_live',
      titleAr: 'واجهة بيانات دول العالم الحية (REST Countries API)',
      titleEn: 'REST Countries Live API',
      category: 'APIs',
      repoSlug: 'restcountries.com/v3.1',
      rawUrl: 'https://restcountries.com/v3.1/all?fields=name,capital,region,subregion,languages,currencies',
      format: 'json',
      isApiRepo: true,
      descriptionAr: 'جلب بيانات حية فورية للعواصم والعملات واللغات لجميع دول العالم مباشرة من الـ API.',
      descriptionEn: 'Live REST API providing capitals, currencies, regions & languages worldwide.',
    ),

    // --- AI, CODING & ENGINEERING KNOWLEDGE DATASETS ---
    GithubDatasetSource(
      id: 'awesome_prompts',
      titleAr: 'موسوعة أوامر الذكاء الاصطناعي الاحترافية (Prompts)',
      titleEn: 'Awesome ChatGPT Prompts (170+ Personas)',
      category: 'AI & Prompts',
      repoSlug: 'f/awesome-chatgpt-prompts',
      rawUrl: 'https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv',
      format: 'csv',
      descriptionAr: 'مئات الشخصيات والأوامر الاحترافية الجاهزة للبرمجة والطب والتسويق والتعليم.',
      descriptionEn: 'Curated library of 170+ expert AI system prompts and specialist roles.',
    ),
    GithubDatasetSource(
      id: 'arabic_prog_books',
      titleAr: 'موسوعة كتب ومصادر البرمجة العربية',
      titleEn: 'Arabic Free Programming Books Corpus',
      category: 'Arabic Tech',
      repoSlug: 'EbookFoundation/free-programming-books',
      rawUrl:
          'https://raw.githubusercontent.com/EbookFoundation/free-programming-books/main/books/free-programming-books-ar.md',
      format: 'md',
      descriptionAr: 'قاعدة بيانات ضخمة باللغة العربية لكتب ومصادر لغات البرمجة وهندسة البرمجيات.',
      descriptionEn: 'Massive Arabic programming books and engineering reference index.',
    ),
    GithubDatasetSource(
      id: 'awesome_flutter',
      titleAr: 'موسوعة Flutter و Dart الاحترافية',
      titleEn: 'Awesome Flutter & Dart Master Knowledge',
      category: 'Coding',
      repoSlug: 'Solido/awesome-flutter',
      rawUrl: 'https://raw.githubusercontent.com/Solido/awesome-flutter/master/README.md',
      format: 'md',
      descriptionAr: 'أفضل مكتبات ومعمارية وأدوات Flutter و Dart لتقوية إجابات البرمجة ومختبر الكود.',
      descriptionEn: 'Comprehensive Flutter packages, architecture patterns, UI kits & tutorials.',
    ),
    GithubDatasetSource(
      id: 'awesome_python',
      titleAr: 'موسوعة Python والذكاء الاصطناعي',
      titleEn: 'Awesome Python Frameworks & AI Tools',
      category: 'Coding',
      repoSlug: 'vinta/awesome-python',
      rawUrl: 'https://raw.githubusercontent.com/vinta/awesome-python/master/README.md',
      format: 'md',
      descriptionAr: 'دليل شامل لمكتبات بايثون في الذكاء الاصطناعي والبيانات والويب والأتمتة.',
      descriptionEn: 'Curated encyclopedia of Python frameworks, AI libraries, and dev tools.',
    ),
    GithubDatasetSource(
      id: 'system_design_primer',
      titleAr: 'مرجع هندسة الأنظمة العملاقة (System Design)',
      titleEn: 'System Design Primer Architecture Guide',
      category: 'Coding',
      repoSlug: 'donnemartin/system-design-primer',
      rawUrl: 'https://raw.githubusercontent.com/donnemartin/system-design-primer/master/README.md',
      format: 'md',
      descriptionAr: 'مرجع هندسة النظم الموزعة، قواعد البيانات، الكاش، ومعمارية التطبيقات الضخمة.',
      descriptionEn: 'Scalable architecture, caching, databases, load balancing & distributed systems.',
    ),
    GithubDatasetSource(
      id: 'build_your_own_x',
      titleAr: 'موسوعة بناء التقنيات من الصفر (Build Your Own X)',
      titleEn: 'Build Your Own X Engineering Tutorials',
      category: 'Coding',
      repoSlug: 'codecrafters-io/build-your-own-x',
      rawUrl: 'https://raw.githubusercontent.com/codecrafters-io/build-your-own-x/master/README.md',
      format: 'md',
      descriptionAr: 'شروحات عملية لبناء قواعد بيانات ومحركات بحث ومترجمات وتطبيقات من الصفر.',
      descriptionEn: 'Hands-on guides to building databases, compilers, OS, neural nets & more.',
    ),
    GithubDatasetSource(
      id: 'coding_interview_uni',
      titleAr: 'جامعة الخوارزميات وهياكل البيانات',
      titleEn: 'Coding Interview University (CS & Algorithms)',
      category: 'Coding',
      repoSlug: 'jwasham/coding-interview-university',
      rawUrl: 'https://raw.githubusercontent.com/jwasham/coding-interview-university/main/README.md',
      format: 'md',
      descriptionAr: 'مرجع شامل في علوم الحاسب، الخوارزميات، هياكل البيانات، وتعقيد الوقت.',
      descriptionEn: 'Complete computer science, data structures, and algorithms study plan.',
    ),

    // --- WORLD KNOWLEDGE & LANGUAGES ---
    GithubDatasetSource(
      id: 'world_countries',
      titleAr: 'قاعدة بيانات دول العالم (عربي وإنجليزي)',
      titleEn: 'World Countries Encyclopedia (250+ Nations)',
      category: 'World Data',
      repoSlug: 'mledoze/countries',
      rawUrl: 'https://raw.githubusercontent.com/mledoze/countries/master/countries.json',
      format: 'json',
      descriptionAr: 'بيانات شاملة لـ 250 دولة: العواصم، اللغات، العملات، المناطق، والأسماء العربية.',
      descriptionEn: 'Complete structured dataset of 250+ countries, capitals, currencies & Arabic names.',
    ),
    GithubDatasetSource(
      id: 'quotes_mega',
      titleAr: 'موسوعة الاقتباسات والحكم العالمية (+5000)',
      titleEn: 'Mega Quotes & Wisdom Database (5000+)',
      category: 'Literature',
      repoSlug: 'JamesFT/Database-Quotes-JSON',
      rawUrl: 'https://raw.githubusercontent.com/JamesFT/Database-Quotes-JSON/master/quotes.json',
      format: 'json',
      descriptionAr: 'آلاف الاقتباسات العالمية والمؤلفين للاستشهاد والكتابة الإبداعية.',
      descriptionEn: 'Thousands of famous quotes and authors for writing & inspiration.',
    ),
    GithubDatasetSource(
      id: 'english_10k',
      titleAr: 'معجم أهم 10,000 كلمة إنجليزية شائعة',
      titleEn: 'Google 10,000 Most Common English Words',
      category: 'English',
      repoSlug: 'first20hours/google-10000-english',
      rawUrl:
          'https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-usa.txt',
      format: 'txt',
      descriptionAr: 'أهم المفردات الإنجليزية الأكثر استخداماً لتقوية اللغة والترجمة.',
      descriptionEn: 'Top 10,000 most frequently used English words corpus.',
    ),
    GithubDatasetSource(
      id: 'awesome_master',
      titleAr: 'الفهرس العملاق لمشاريع GitHub (Awesome)',
      titleEn: 'Sindre Sorhus Awesome Master Index',
      category: 'Knowledge',
      repoSlug: 'sindresorhus/awesome',
      rawUrl: 'https://raw.githubusercontent.com/sindresorhus/awesome/main/readme.md',
      format: 'md',
      descriptionAr: 'الفهرس الرئيسي لأهم قوائم المعرفة والتقنية والذكاء الاصطناعي على GitHub.',
      descriptionEn: 'Master index of awesome lists covering AI, CS, science, and tools.',
    ),
  ];

  final NimoLocalDbNotifier _localDb;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 22),
      receiveTimeout: const Duration(seconds: 50),
      responseType: ResponseType.plain,
      headers: {'Accept': 'application/json, text/plain, */*'},
    ),
  );

  GithubKnowledgeNotifier(this._localDb)
      : super(const GithubKnowledgeState(sources: builtInSources)) {
    _loadCached();
  }

  /// Injects a source's parsed KnowledgeEntry list directly into NimoLocalDbNotifier's core index.
  void _injectIntoAppDb(GithubDatasetSource src, List<KnowledgeEntry> entries) {
    final categoryTag = src.isApiRepo ? 'github_apis' : 'github_${src.category.toLowerCase().replaceAll(RegExp(r"""[^a-z0-9]+"""), '_')}';
    final records = <LocalDbRecord>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      records.add(
        LocalDbRecord(
          id: 900000 + i,
          category: categoryTag,
          title: e.title,
          body: e.content,
          keywords: '${src.repoSlug} ${src.titleAr} ${src.titleEn} ${src.category} ${e.title}',
          sourceId: src.id,
        ),
      );
    }
    _localDb.injectSourceRecords(src.id, records);
  }

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ragEnabled = prefs.getBool(_kRagEnabledKey) ?? true;

      final customRaw = prefs.getString(_kCustomSourcesKey);
      final allSources = List<GithubDatasetSource>.from(builtInSources);
      if (customRaw != null && customRaw.isNotEmpty) {
        final decoded = jsonDecode(customRaw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            allSources.add(GithubDatasetSource.fromJson(item));
          }
        }
      }

      final metaRaw = prefs.getString(_kMetaKey);
      final Map<String, DateTime> timestamps = {};
      if (metaRaw != null && metaRaw.isNotEmpty) {
        final metaMap = jsonDecode(metaRaw) as Map<String, dynamic>;
        metaMap.forEach((k, v) {
          final dt = DateTime.tryParse(v.toString());
          if (dt != null) timestamps[k] = dt;
        });
      }

      final Map<String, List<KnowledgeEntry>> entriesMap = {};
      for (final src in allSources) {
        final raw = prefs.getString('$_kEntriesPrefix${src.id}');
        if (raw != null && raw.isNotEmpty) {
          final list = jsonDecode(raw) as List<dynamic>;
          final parsed = list
              .whereType<Map<String, dynamic>>()
              .map(KnowledgeEntry.fromJson)
              .toList();
          entriesMap[src.id] = parsed;
          if (parsed.isNotEmpty) {
            _injectIntoAppDb(src, parsed);
          }
        }
      }

      state = state.copyWith(
        sources: allSources,
        entriesBySource: entriesMap,
        lastSyncedBySource: timestamps,
        ragEnabled: ragEnabled,
      );
    } catch (_) {}
  }

  Future<void> setRagEnabled(bool enabled) async {
    state = state.copyWith(ragEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRagEnabledKey, enabled);
    } catch (_) {}
  }

  /// Auto-converts GitHub blob URLs, tree URLs, and plain repo URLs into directly fetchable raw URLs.
  static String normalizeGithubUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.contains('github.com/') && trimmed.contains('/blob/')) {
      return trimmed
          .replaceFirst('https://github.com/', 'https://raw.githubusercontent.com/')
          .replaceFirst('http://github.com/', 'https://raw.githubusercontent.com/')
          .replaceFirst('/blob/', '/');
    }
    // Plain GitHub repo URL like https://github.com/owner/repo -> default to README.md on main
    final repoMatch = RegExp(r"""^https?://github\.com/([^/\s]+)/([^/\s]+)$""").firstMatch(trimmed);
    if (repoMatch != null) {
      final owner = repoMatch.group(1)!;
      final repo = repoMatch.group(2)!.replaceAll(RegExp(r"""\.git$"""), '');
      return 'https://raw.githubusercontent.com/$owner/$repo/main/README.md';
    }
    return trimmed;
  }

  /// Adds ANY user-supplied GitHub repo, raw dataset URL, or live REST JSON API and immediately injects it.
  Future<bool> addCustomSource({
    required String title,
    required String url,
    String category = 'Custom GitHub',
    bool isApiRepo = false,
  }) async {
    final rawUrl = normalizeGithubUrl(url);
    if (!rawUrl.startsWith('http')) return false;

    String format = 'auto';
    final lower = rawUrl.toLowerCase();
    if (lower.endsWith('.json') || lower.contains('format=json') || isApiRepo) {
      format = 'json';
    } else if (lower.endsWith('.jsonl') || lower.endsWith('.ndjson')) {
      format = 'jsonl';
    } else if (lower.endsWith('.csv')) {
      format = 'csv';
    } else if (lower.endsWith('.md')) {
      format = 'md';
    } else if (lower.endsWith('.txt')) {
      format = 'txt';
    }

    final uri = Uri.tryParse(rawUrl);
    final slug = (uri != null && uri.pathSegments.length >= 2)
        ? '${uri.pathSegments[0]}/${uri.pathSegments[1]}'
        : (uri?.host ?? 'github');

    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final src = GithubDatasetSource(
      id: id,
      titleAr: title.trim().isEmpty ? 'مصدر مستورد: $slug' : title.trim(),
      titleEn: title.trim().isEmpty ? 'Imported: $slug' : title.trim(),
      category: category,
      repoSlug: slug,
      rawUrl: rawUrl,
      format: format,
      descriptionAr: rawUrl,
      descriptionEn: rawUrl,
      isCustom: true,
      isApiRepo: isApiRepo,
    );

    final updatedSources = [src, ...state.sources];
    state = state.copyWith(sources: updatedSources);
    try {
      final prefs = await SharedPreferences.getInstance();
      final customs = updatedSources.where((s) => s.isCustom).map((s) => s.toJson()).toList();
      await prefs.setString(_kCustomSourcesKey, jsonEncode(customs));
    } catch (_) {}

    return syncSource(src.id);
  }

  Future<void> removeCustomSource(String sourceId) async {
    final updatedSources = state.sources.where((s) => s.id != sourceId).toList();
    final updatedEntries = Map<String, List<KnowledgeEntry>>.from(state.entriesBySource)..remove(sourceId);
    final updatedDates = Map<String, DateTime>.from(state.lastSyncedBySource)..remove(sourceId);

    // Also remove from core app database inverted index!
    _localDb.removeSourceRecords(sourceId);

    state = state.copyWith(
      sources: updatedSources,
      entriesBySource: updatedEntries,
      lastSyncedBySource: updatedDates,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kEntriesPrefix$sourceId');
      final customs = updatedSources.where((s) => s.isCustom).map((s) => s.toJson()).toList();
      await prefs.setString(_kCustomSourcesKey, jsonEncode(customs));
    } catch (_) {}
  }

  /// Downloads, parses, caches locally, AND injects the dataset straight into NimoLocalDbNotifier!
  Future<bool> syncSource(String sourceId) async {
    final src = state.sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => builtInSources.first,
    );

    final nextSyncing = Set<String>.from(state.syncingIds)..add(sourceId);
    state = state.copyWith(syncingIds: nextSyncing, clearError: true, clearBanner: true);

    try {
      String rawText = await _fetchWithBranchFallback(src.rawUrl);
      if (rawText.trim().isEmpty) {
        throw Exception('Empty response from source.');
      }

      final parsed = _parseRawDataset(src, rawText);
      if (parsed.isEmpty) {
        throw Exception('No parseable records found in file.');
      }
      final capped = parsed.length > 1500 ? parsed.sublist(0, 1500) : parsed;

      // CORE INJECTION: Inject every record straight into Nimo's unified inverted-index DB!
      _injectIntoAppDb(src, capped);

      final updatedEntries = Map<String, List<KnowledgeEntry>>.from(state.entriesBySource);
      updatedEntries[sourceId] = capped;

      final updatedDates = Map<String, DateTime>.from(state.lastSyncedBySource);
      updatedDates[sourceId] = DateTime.now();

      final doneSyncing = Set<String>.from(state.syncingIds)..remove(sourceId);
      state = state.copyWith(
        entriesBySource: updatedEntries,
        lastSyncedBySource: updatedDates,
        syncingIds: doneSyncing,
        lastSuccessBanner: 'تم استيراد وحقن ${capped.length} سجل من ${src.repoSlug} داخل قاعدة بيانات التطبيق بنجاح!',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kEntriesPrefix$sourceId',
        jsonEncode(capped.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _kMetaKey,
        jsonEncode(updatedDates.map((k, v) => MapEntry(k, v.toIso8601String()))),
      );
      return true;
    } catch (e) {
      final doneSyncing = Set<String>.from(state.syncingIds)..remove(sourceId);
      state = state.copyWith(
        syncingIds: doneSyncing,
        lastError: 'فشل استيراد ${src.repoSlug}: $e',
      );
      return false;
    }
  }

  /// Tries `main` and automatically falls back to `master` (and lowercase `readme.md`) for GitHub raw URLs.
  Future<String> _fetchWithBranchFallback(String url) async {
    try {
      final res = await _dio.get<String>(url);
      return res.data ?? '';
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 && url.contains('raw.githubusercontent.com')) {
        final candidates = <String>[];
        if (url.contains('/main/')) {
          candidates.add(url.replaceFirst('/main/', '/master/'));
          candidates.add(url.replaceFirst('/main/README.md', '/main/readme.md'));
          candidates.add(url.replaceFirst('/main/README.md', '/master/readme.md'));
        } else if (url.contains('/master/')) {
          candidates.add(url.replaceFirst('/master/', '/main/'));
          candidates.add(url.replaceFirst('/master/README.md', '/master/readme.md'));
        }
        for (final alt in candidates) {
          try {
            final res = await _dio.get<String>(alt);
            if ((res.data ?? '').trim().isNotEmpty) return res.data!;
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  Future<void> syncAllBuiltIn({bool apisOnly = false}) async {
    final targets = apisOnly
        ? state.sources.where((s) => s.isApiRepo).toList()
        : state.sources;
    for (final src in targets) {
      await syncSource(src.id);
    }
  }

  List<KnowledgeEntry> _parseRawDataset(GithubDatasetSource src, String raw) {
    final trimmedRaw = raw.trim();
    String effectiveFormat = src.format;
    if (effectiveFormat == 'auto') {
      if (trimmedRaw.startsWith('[') || trimmedRaw.startsWith('{')) {
        effectiveFormat = 'json';
      } else if (trimmedRaw.contains('##') || trimmedRaw.contains('](')) {
        effectiveFormat = 'md';
      } else if (trimmedRaw.split('\n').first.contains(',')) {
        effectiveFormat = 'csv';
      } else {
        effectiveFormat = 'txt';
      }
    }

    if (effectiveFormat == 'jsonl') {
      return _parseJsonLines(src, trimmedRaw);
    }
    if (effectiveFormat == 'csv') {
      return _parseCsv(src, trimmedRaw);
    }
    if (effectiveFormat == 'json') {
      return _parseJson(src, trimmedRaw);
    }
    if (effectiveFormat == 'md') {
      return _parseMarkdown(src, trimmedRaw);
    }
    return _parsePlainText(src, trimmedRaw);
  }

  List<KnowledgeEntry> _parseJsonLines(GithubDatasetSource src, String raw) {
    final entries = <KnowledgeEntry>[];
    final lines = const LineSplitter().convert(raw);
    for (final line in lines) {
      if (entries.length >= 1200) break;
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        final obj = jsonDecode(t);
        if (obj is Map) {
          entries.add(_mapToEntry(src, obj));
        }
      } catch (_) {}
    }
    return entries;
  }

  List<KnowledgeEntry> _parseCsv(GithubDatasetSource src, String raw) {
    final entries = <KnowledgeEntry>[];
    final lines = const LineSplitter().convert(raw);
    for (int i = 1; i < lines.length && entries.length < 1200; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = _splitCsvLine(line);
      if (parts.length >= 2) {
        final title = parts[0].replaceAll('"', '').trim();
        final content = parts.sublist(1).join(' | ').replaceAll('"', '').trim();
        if (title.isNotEmpty && content.isNotEmpty) {
          entries.add(KnowledgeEntry(
            sourceId: src.id,
            sourceTitle: src.titleEn,
            title: title.length > 120 ? title.substring(0, 120) : title,
            content: content.length > 520 ? '${content.substring(0, 520)}...' : content,
          ));
        }
      }
    }
    return entries;
  }

  List<KnowledgeEntry> _parseJson(GithubDatasetSource src, String raw) {
    final entries = <KnowledgeEntry>[];
    final decoded = jsonDecode(raw);

    if (decoded is List) {
      for (final item in decoded) {
        if (entries.length >= 1200) break;
        if (item is Map) {
          entries.add(_mapToEntry(src, item));
        } else if (item != null) {
          entries.add(KnowledgeEntry(
            sourceId: src.id,
            sourceTitle: src.titleEn,
            title: '${src.titleEn} #${entries.length + 1}',
            content: item.toString(),
          ));
        }
      }
    } else if (decoded is Map) {
      // Handle nested collection keys like { "entries": [...], "data": [...], "items": [...], "apis": [...] }
      List<dynamic>? nestedList;
      for (final key in ['entries', 'data', 'items', 'results', 'records', 'apis', 'prompts', 'quotes', 'resources']) {
        if (decoded[key] is List) {
          nestedList = decoded[key] as List<dynamic>;
          break;
        }
      }

      if (nestedList != null) {
        for (final item in nestedList) {
          if (entries.length >= 1200) break;
          if (item is Map) {
            entries.add(_mapToEntry(src, item));
          }
        }
      } else {
        // Handle key-value maps (like APIs.guru /v2/list.json where keys are API domains!)
        for (final kv in decoded.entries) {
          if (entries.length >= 1200) break;
          final k = kv.key.toString();
          final v = kv.value;
          if (v is Map) {
            // Check APIs.guru structure: preferred + versions[preferred].info.description
            final preferred = v['preferred']?.toString();
            final versions = v['versions'];
            if (preferred != null && versions is Map && versions[preferred] is Map) {
              final info = (versions[preferred] as Map)['info'];
              final title = (info is Map ? info['title'] : k)?.toString() ?? k;
              final desc = (info is Map ? info['description'] : '')?.toString() ?? '';
              final swagger = (versions[preferred] as Map)['swaggerUrl']?.toString() ?? '';
              final cleanDesc = desc.replaceAll(RegExp(r"""<[^>]*>"""), ' ').replaceAll(RegExp(r"""\s+"""), ' ').trim();
              entries.add(KnowledgeEntry(
                sourceId: src.id,
                sourceTitle: src.titleAr,
                title: '$title ($k)',
                content: '${cleanDesc.length > 300 ? '${cleanDesc.substring(0, 300)}...' : cleanDesc}${swagger.isNotEmpty ? ' | OpenAPI: $swagger' : ''}',
              ));
            } else {
              entries.add(_mapToEntry(src, v, fallbackTitle: k));
            }
          } else {
            entries.add(KnowledgeEntry(
              sourceId: src.id,
              sourceTitle: src.titleEn,
              title: k,
              content: v.toString(),
            ));
          }
        }
      }
    }
    return entries;
  }

  KnowledgeEntry _mapToEntry(GithubDatasetSource src, Map item, {String? fallbackTitle}) {
    if (src.id == 'world_countries' || src.id == 'rest_countries_live') {
      final nameMap = item['name'];
      final common = (nameMap is Map ? nameMap['common'] : item['name'])?.toString() ?? '';
      final translations = item['translations'];
      final ara = (translations is Map && translations['ara'] is Map)
          ? (translations['ara']['common'] ?? '').toString()
          : '';
      final capitalList = item['capital'];
      final capital = (capitalList is List && capitalList.isNotEmpty)
          ? capitalList.first.toString()
          : '';
      final region = (item['region'] ?? '').toString();
      final subregion = (item['subregion'] ?? '').toString();
      return KnowledgeEntry(
        sourceId: src.id,
        sourceTitle: src.titleAr,
        title: ara.isNotEmpty ? '$common ($ara)' : (common.isEmpty ? (fallbackTitle ?? 'Country') : common),
        content: 'Capital: $capital | Region: $region ($subregion)',
      );
    }

    if (item['quoteText'] != null) {
      final q = item['quoteText'].toString().trim();
      final a = (item['quoteAuthor'] ?? 'Unknown').toString().trim();
      return KnowledgeEntry(
        sourceId: src.id,
        sourceTitle: src.titleEn,
        title: a.isEmpty ? 'Quote' : a,
        content: q,
      );
    }

    final title = (item['API'] ??
            item['title'] ??
            item['name'] ??
            item['act'] ??
            item['question'] ??
            item['key'] ??
            fallbackTitle ??
            'Record')
        .toString();

    final desc = item['Description'] ??
        item['description'] ??
        item['content'] ??
        item['prompt'] ??
        item['answer'] ??
        item['text'] ??
        item['body'];
    final link = (item['Link'] ?? item['url'] ?? item['href'] ?? '').toString();
    final cat = (item['Category'] ?? item['category'] ?? '').toString();
    final bodyText = desc != null
        ? '${desc.toString()}${cat.isNotEmpty ? ' | Category: $cat' : ''}${link.isNotEmpty ? ' | URL: $link' : ''}'
        : jsonEncode(item);

    return KnowledgeEntry(
      sourceId: src.id,
      sourceTitle: src.titleEn,
      title: title.length > 110 ? title.substring(0, 110) : title,
      content: bodyText.length > 480 ? '${bodyText.substring(0, 480)}...' : bodyText,
    );
  }

  List<KnowledgeEntry> _parseMarkdown(GithubDatasetSource src, String raw) {
    final entries = <KnowledgeEntry>[];
    final lines = const LineSplitter().convert(raw);
    String currentHeading = src.titleEn;
    final linkRegex = RegExp(r"""\[([^\]]+)\]\((https?://[^)]+)\)""");

    for (final line in lines) {
      if (entries.length >= 1200) break;
      final trimmed = line.trim();
      if (trimmed.startsWith('##')) {
        currentHeading = trimmed.replaceAll('#', '').trim();
      } else if (trimmed.startsWith('|') && trimmed.contains('http')) {
        final cols = trimmed.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        if (cols.length >= 2) {
          final title = cols[0].replaceAll(RegExp(r"""[\[\]\(\)]"""), ' ').trim();
          final desc = cols.sublist(1).join(' | ');
          entries.add(KnowledgeEntry(
            sourceId: src.id,
            sourceTitle: src.titleEn,
            title: '$currentHeading: $title',
            content: desc.length > 340 ? '${desc.substring(0, 340)}...' : desc,
          ));
        }
      } else if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
        final m = linkRegex.firstMatch(trimmed);
        if (m != null) {
          final label = m.group(1) ?? '';
          final url = m.group(2) ?? '';
          entries.add(KnowledgeEntry(
            sourceId: src.id,
            sourceTitle: src.titleAr,
            title: '$currentHeading — $label',
            content: '${trimmed.replaceAll(RegExp(r"""^[\*\-]\s+"""), '')} ($url)',
          ));
        } else if (trimmed.length > 18) {
          final clean = trimmed.replaceAll(RegExp(r"""^[\*\-]\s+"""), '');
          entries.add(KnowledgeEntry(
            sourceId: src.id,
            sourceTitle: src.titleAr,
            title: currentHeading,
            content: clean.length > 340 ? '${clean.substring(0, 340)}...' : clean,
          ));
        }
      }
    }

    // Fallback for plain narrative markdown without bullet links
    if (entries.isEmpty) {
      return _parsePlainText(src, raw);
    }
    return entries;
  }

  List<KnowledgeEntry> _parsePlainText(GithubDatasetSource src, String raw) {
    final entries = <KnowledgeEntry>[];
    final lines = const LineSplitter().convert(raw).where((l) => l.trim().isNotEmpty).toList();
    const chunkSize = 20;
    for (int i = 0; i < lines.length && entries.length < 800; i += chunkSize) {
      final end = math.min(i + chunkSize, lines.length);
      final slice = lines.sublist(i, end);
      final joined = slice.join(' | ');
      entries.add(KnowledgeEntry(
        sourceId: src.id,
        sourceTitle: src.titleEn,
        title: '${src.titleEn} #${entries.length + 1}',
        content: joined.length > 480 ? '${joined.substring(0, 480)}...' : joined,
      ));
    }
    return entries;
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString());
    return result;
  }

  /// Fast local RAG search across all cached GitHub datasets.
  List<KnowledgeEntry> search(String query, {int limit = 8}) {
    final cleanQuery = _normalizeText(query);
    if (cleanQuery.isEmpty) return const [];
    final tokens = cleanQuery
        .split(RegExp(r"""\s+"""))
        .where((t) => t.length >= 2)
        .toSet();
    if (tokens.isEmpty) return const [];

    final scored = <_ScoredEntry>[];
    for (final list in state.entriesBySource.values) {
      for (final entry in list) {
        final hayTitle = _normalizeText(entry.title);
        final hayContent = _normalizeText(entry.content);
        int score = 0;
        if (hayTitle.contains(cleanQuery)) score += 12;
        if (hayContent.contains(cleanQuery)) score += 8;
        for (final t in tokens) {
          if (hayTitle.contains(t)) score += 5;
          if (hayContent.contains(t)) score += 2;
        }
        if (score > 0) {
          scored.add(_ScoredEntry(entry, score));
        }
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((s) => s.entry).toList();
  }

  /// Builds a concise RAG context block to inject into the AI system prompt.
  String buildRagContext(String userQuery) {
    if (!state.ragEnabled || state.totalEntries == 0) return '';
    final hits = search(userQuery, limit: 5);
    if (hits.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('\n[INJECTED GITHUB & PUBLIC API KNOWLEDGE CONTEXT — USE WHEN RELEVANT]:');
    for (final h in hits) {
      buf.writeln('- [${h.sourceTitle}] ${h.title}: ${h.content}');
    }
    return buf.toString();
  }

  static String _normalizeText(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"""[أإآ]"""), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r"""[\u064B-\u065F]"""), '')
        .trim();
  }
}

class _ScoredEntry {
  final KnowledgeEntry entry;
  final int score;
  const _ScoredEntry(this.entry, this.score);
}

final githubKnowledgeProvider =
    StateNotifierProvider<GithubKnowledgeNotifier, GithubKnowledgeState>(
  (ref) => GithubKnowledgeNotifier(ref.read(nimoLocalDbProvider.notifier)),
);

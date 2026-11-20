import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_animations.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';

/// Nimo v7.0 Apex — Clean, Fast Unified Knowledge & GitHub/API Database Hub.
/// Completely cleaned of widget jargon; features debounced instant search,
/// personal note creation, and one-tap "Ask Nimo" directly from any record!
class GithubDbScreen extends ConsumerStatefulWidget {
  const GithubDbScreen({super.key});

  @override
  ConsumerState<GithubDbScreen> createState() => _GithubDbScreenState();
}

class _GithubDbScreenState extends ConsumerState<GithubDbScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _customTitleCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  Timer? _searchDebounce;

  String? _selectedCategory;
  String _repoFilter = 'all';
  String _customCategory = 'APIs';
  bool _customIsApi = true;
  bool _isSyncingAll = false;
  bool _isAddingCustom = false;
  List<LocalDbRecord> _unifiedHits = [];

  static const Map<String, String> _catLabelsAr = {
    'custom_notes': 'ملاحظاتي الشخصية',
    'github_apis': 'مستودعات APIs',
    'github_coding': 'البرمجة',
    'github_ai_prompts': 'أوامر الذكاء',
    'github_arabic_tech': 'تقنية عربية',
    'github_world_data': 'دول العالم',
    'github_custom_github': 'مصادر مخصصة',
    'coding': 'البرمجة',
    'code_bank': 'بنك الأكواد',
    'code_recipes': 'حلول برمجية',
    'prompts': 'أوامر AI',
    'english': 'الإنجليزية',
    'dictionary': 'القاموس',
    'science': 'العلوم',
    'world': 'دول العالم',
    'mobile_dev': 'الموبايل',
    'backend_cloud': 'الخوادم',
    'business': 'الأعمال',
    'fitness': 'اللياقة',
    'cybersecurity': 'الأمن السيبراني',
    'ai': 'الذكاء الاصطناعي',
    'general_knowledge': 'معرفة عامة',
    'engineering': 'الهندسة',
    'history': 'التاريخ',
    'design': 'التصميم',
    'psychology': 'علم النفس',
    'finance': 'المال والأعمال',
    'future_tech': 'تقنيات المستقبل',
    'troubleshooting': 'حلول الأعطال',
    'glossary': 'المصطلحات',
    'reference': 'مراجع سريعة',
    'wisdom': 'تطوير الذات',
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch('');
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _customTitleCtrl.dispose();
    _customUrlCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _runSearch(query);
    });
  }

  void _runSearch(String query) {
    final local = ref
        .read(nimoLocalDbProvider.notifier)
        .search(query.trim(), category: _selectedCategory, limit: 30);
    setState(() => _unifiedHits = local);
  }

  Future<void> _syncAll({bool apisOnly = false}) async {
    if (_isSyncingAll) return;
    NimoSoundFx.click();
    setState(() => _isSyncingAll = true);
    await ref.read(githubKnowledgeProvider.notifier).syncAllBuiltIn(apisOnly: apisOnly);
    if (mounted) {
      setState(() => _isSyncingAll = false);
      _runSearch(_searchCtrl.text);
    }
  }

  Future<void> _submitCustomImport() async {
    final url = _customUrlCtrl.text.trim();
    if (url.isEmpty || _isAddingCustom) return;
    NimoSoundFx.pop();
    setState(() => _isAddingCustom = true);

    final ok = await ref.read(githubKnowledgeProvider.notifier).addCustomSource(
          title: _customTitleCtrl.text.trim(),
          url: url,
          category: _customCategory,
          isApiRepo: _customIsApi,
        );

    if (!mounted) return;
    setState(() => _isAddingCustom = false);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    if (ok) {
      _customTitleCtrl.clear();
      _customUrlCtrl.clear();
      _runSearch(_searchCtrl.text);
      _tabCtrl.animateTo(0);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          ok
              ? (isAr ? 'تم استيراد المصدر وإضافته لقاعدة البيانات بنجاح!' : 'Imported into Nimo database!')
              : (isAr
                  ? 'تعذّر تحميل الرابط — تأكد أنه رابط GitHub أو JSON API صالح.'
                  : 'Failed to fetch URL — check that it is a valid GitHub or JSON API link.'),
        ),
      ),
    );
  }

  void _showAddPersonalNoteDialog(bool isAr) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'إضافة معلومة شخصية لقاعدة Nimo' : 'Add Personal Knowledge Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: isAr ? 'العنوان' : 'Title',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: isAr ? 'المحتوى أو التفاصيل' : 'Details',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isNotEmpty && bodyCtrl.text.trim().isNotEmpty) {
                ref.read(nimoLocalDbProvider.notifier).addCustomNote(
                      title: titleCtrl.text,
                      body: bodyCtrl.text,
                    );
                Navigator.pop(ctx);
                _runSearch(_searchCtrl.text);
              }
            },
            child: Text(isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _askNimoAboutRecord(LocalDbRecord rec, bool isAr) {
    NimoSoundFx.click();
    final prompt = isAr
        ? 'اشرح لي بالتفصيل وأعطني أمثلة عملية حول: ${rec.title}'
        : 'Explain in detail with practical examples: ${rec.title}';
    ref.read(chatPrefillPromptProvider.notifier).state = prompt;
    context.go('/chat');
  }

  List<GithubDatasetSource> _filteredSources(List<GithubDatasetSource> all) {
    switch (_repoFilter) {
      case 'apis':
        return all.where((s) => s.isApiRepo || s.category == 'APIs').toList();
      case 'coding':
        return all.where((s) => s.category == 'Coding' || s.category == 'Arabic Tech').toList();
      case 'ai':
        return all.where((s) => s.category == 'AI & Prompts' || s.isCustom).toList();
      case 'knowledge':
        return all
            .where((s) => !s.isApiRepo && s.category != 'Coding' && s.category != 'Arabic Tech' && s.category != 'AI & Prompts')
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gh = ref.watch(githubKnowledgeProvider);
    final localDb = ref.watch(nimoLocalDbProvider);
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final filteredSources = _filteredSources(gh.sources);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'قواعد البيانات الذكية' : 'Smart Databases'),
        actions: [
          IconButton(
            tooltip: isAr ? 'إضافة معلومة شخصية' : 'Add Note',
            icon: const Icon(CupertinoIcons.plus_circle_fill, size: 22),
            onPressed: () => _showAddPersonalNoteDialog(isAr),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(
              icon: const Icon(CupertinoIcons.cloud_download_fill, size: 18),
              text: isAr ? 'المستودعات (${gh.sources.length})' : 'Repos (${gh.sources.length})',
            ),
            Tab(
              icon: const Icon(CupertinoIcons.search, size: 18),
              text: isAr ? 'بحث (${localDb.totalRecords})' : 'Search (${localDb.totalRecords})',
            ),
            Tab(
              icon: const Icon(CupertinoIcons.add_circled_solid, size: 18),
              text: isAr ? 'رابط مخصص' : 'Custom URL',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ================= TAB 1: GITHUB & API REPOSITORIES =================
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              NimoEntrance(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const IosIconBadge(
                              icon: CupertinoIcons.layers_alt_fill,
                              color: TalkoraColors.iosIndigo,
                              size: 46,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      NimoAnimatedCounter(
                                        value: localDb.totalRecords,
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isAr ? 'سجل معرفي جاهز' : 'Indexed Records',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isAr
                                        ? '${localDb.builtInRecords} مدمج + ${localDb.injectedRecords} من ${localDb.injectedSourcesCount} مصدر'
                                        : '${localDb.builtInRecords} built-in + ${localDb.injectedRecords} imported',
                                    style: theme.textTheme.bodySmall?.copyWith(color: TalkoraColors.iosGreen),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                isAr
                                    ? 'ربط قواعد البيانات تلقائياً بإجابات Nimo'
                                    : 'Auto-connect database to Nimo AI answers',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            CupertinoSwitch(
                              value: gh.ragEnabled,
                              activeTrackColor: TalkoraColors.iosGreen,
                              onChanged: (v) {
                                NimoSoundFx.click();
                                ref.read(githubKnowledgeProvider.notifier).setRagEnabled(v);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isSyncingAll ? null : () => _syncAll(apisOnly: true),
                                icon: _isSyncingAll
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CupertinoActivityIndicator(color: Colors.white),
                                      )
                                    : const Icon(CupertinoIcons.globe, size: 17),
                                label: Text(
                                  isAr ? 'استيراد APIs' : 'Sync APIs',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _isSyncingAll ? null : () => _syncAll(apisOnly: false),
                                icon: const Icon(CupertinoIcons.cloud_download_fill, size: 17),
                                label: Text(
                                  isAr ? 'استيراد الكل' : 'Sync All',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (gh.lastSuccessBanner != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TalkoraColors.iosGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TalkoraColors.iosGreen.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.checkmark_seal_fill, color: TalkoraColors.iosGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gh.lastSuccessBanner!,
                          style: const TextStyle(color: TalkoraColors.iosGreen, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (gh.lastError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TalkoraColors.iosRed.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    gh.lastError!,
                    style: const TextStyle(color: TalkoraColors.iosRed, fontSize: 12.5),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip('all', isAr ? 'الكل (${gh.sources.length})' : 'All (${gh.sources.length})'),
                    _filterChip('apis', isAr ? 'مستودعات APIs' : 'API Repos'),
                    _filterChip('coding', isAr ? 'البرمجة والهندسة' : 'Coding'),
                    _filterChip('ai', isAr ? 'الذكاء والمخصصة' : 'AI & Custom'),
                    _filterChip('knowledge', isAr ? 'المعرفة واللغات' : 'Knowledge'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              ...filteredSources.map((src) {
                final count = gh.entriesBySource[src.id]?.length ?? 0;
                final syncing = gh.syncingIds.contains(src.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IosIconBadge(
                                icon: src.isApiRepo
                                    ? CupertinoIcons.globe
                                    : (src.isCustom
                                        ? CupertinoIcons.link
                                        : CupertinoIcons.layers_alt_fill),
                                color: src.isApiRepo
                                    ? TalkoraColors.iosTeal
                                    : (count > 0 ? TalkoraColors.iosGreen : TalkoraColors.iosBlue),
                                size: 38,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isAr ? src.titleAr : src.titleEn,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      src.repoSlug,
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (src.isCustom)
                                IconButton(
                                  tooltip: isAr ? 'حذف المصدر' : 'Remove',
                                  icon: const Icon(CupertinoIcons.trash, size: 18, color: TalkoraColors.iosRed),
                                  onPressed: () {
                                    NimoSoundFx.click();
                                    ref.read(githubKnowledgeProvider.notifier).removeCustomSource(src.id);
                                    _runSearch(_searchCtrl.text);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isAr ? src.descriptionAr : src.descriptionEn,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (count > 0)
                                IosStatusPill(
                                  label: isAr ? 'متصل • $count سجل' : 'Synced • $count records',
                                  color: TalkoraColors.iosGreen,
                                  icon: CupertinoIcons.checkmark_seal_fill,
                                )
                              else
                                IosStatusPill(
                                  label: src.isApiRepo ? 'API • ${src.format.toUpperCase()}' : src.format.toUpperCase(),
                                  color: TalkoraColors.iosIndigo,
                                ),
                              syncing
                                  ? const CupertinoActivityIndicator()
                                  : FilledButton.tonalIcon(
                                      onPressed: () async {
                                        NimoSoundFx.click();
                                        await ref.read(githubKnowledgeProvider.notifier).syncSource(src.id);
                                        if (mounted) _runSearch(_searchCtrl.text);
                                      },
                                      icon: Icon(
                                        count > 0 ? CupertinoIcons.refresh : CupertinoIcons.arrow_down_circle_fill,
                                        size: 16,
                                      ),
                                      label: Text(
                                        count > 0
                                            ? (isAr ? 'تحديث' : 'Refresh')
                                            : (isAr ? 'استيراد' : 'Import'),
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),

          // ================= TAB 2: UNIFIED INSTANT SEARCH =================
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: isAr
                      ? 'ابحث فورياً في ${localDb.totalRecords} سجل معرفي...'
                      : 'Instant search across ${localDb.totalRecords} records...',
                  prefixIcon: const Icon(CupertinoIcons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: isAr ? 'لصق' : 'Paste',
                        icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                        onPressed: () async {
                          final ok = await NimoClipboardHelper.pasteIntoController(
                            context,
                            _searchCtrl,
                            isAr: isAr,
                          );
                          if (ok) _runSearch(_searchCtrl.text);
                        },
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(CupertinoIcons.clear_circled_solid, size: 18),
                          onPressed: () {
                            NimoSoundFx.click();
                            _searchCtrl.clear();
                            _runSearch('');
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(
                          isAr ? 'الكل (${localDb.totalRecords})' : 'All (${localDb.totalRecords})',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _selectedCategory == null,
                        onSelected: (_) {
                          NimoSoundFx.click();
                          setState(() => _selectedCategory = null);
                          _runSearch(_searchCtrl.text);
                        },
                      ),
                    ),
                    ...localDb.categoryCounts.entries.map((e) {
                      final label = isAr ? (_catLabelsAr[e.key] ?? e.key) : e.key;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text('$label (${e.value})', style: const TextStyle(fontSize: 12)),
                          selected: _selectedCategory == e.key,
                          onSelected: (_) {
                            NimoSoundFx.click();
                            setState(() => _selectedCategory = e.key);
                            _runSearch(_searchCtrl.text);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ..._unifiedHits.map(
                (rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (rec.isInjected) ...[
                                const Icon(CupertinoIcons.cloud_fill, size: 14, color: TalkoraColors.iosTeal),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  rec.title,
                                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.2),
                                ),
                              ),
                              NimoCopyChip(
                                textToCopy: '${rec.title}\n${rec.body}',
                                isAr: isAr,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(rec.body, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              onPressed: () => _askNimoAboutRecord(rec, isAr),
                              icon: const Icon(CupertinoIcons.sparkles, size: 15),
                              label: Text(
                                isAr ? 'اسأل Nimo عن هذا الموضوع' : 'Ask Nimo',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ================= TAB 3: ADD CUSTOM GITHUB / API URL =================
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              IosGroupedSection(
                header: isAr ? 'استيراد رابط GitHub أو API مخصص' : 'IMPORT CUSTOM GITHUB OR JSON API',
                footer: isAr
                    ? 'يدعم روابط مستودعات GitHub الكاملة، وملفات JSON / JSONL / CSV / MD / TXT، وأي رابط REST API عام يعيد JSON.'
                    : 'Supports GitHub repo URLs, raw JSON/JSONL/CSV/MD/TXT files, and live public JSON REST APIs.',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _customTitleCtrl,
                          decoration: InputDecoration(
                            labelText: isAr ? 'اسم المصدر أو المستودع' : 'Dataset / API Name',
                            hintText: isAr ? 'مثال: بيانات طقس أو مرجع برمجي' : 'e.g. Docs or Public API',
                            prefixIcon: const Icon(CupertinoIcons.tag_fill, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            controller: _customUrlCtrl,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: 'GitHub Repo / Raw File / JSON API URL',
                              hintText: 'https://github.com/owner/repo  or  https://api.../data.json',
                              prefixIcon: const Icon(CupertinoIcons.link, size: 18),
                              suffixIcon: IconButton(
                                tooltip: isAr ? 'لصق' : 'Paste',
                                icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 19),
                                onPressed: () => NimoClipboardHelper.pasteIntoController(
                                  context,
                                  _customUrlCtrl,
                                  isAr: isAr,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isAr ? 'تصنيف كمستودع API' : 'Mark as API Repository',
                              style: theme.textTheme.bodyMedium,
                            ),
                            CupertinoSwitch(
                              value: _customIsApi,
                              activeTrackColor: TalkoraColors.iosTeal,
                              onChanged: (v) {
                                setState(() {
                                  _customIsApi = v;
                                  _customCategory = v ? 'APIs' : 'Custom GitHub';
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _isAddingCustom ? null : _submitCustomImport,
                            icon: _isAddingCustom
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CupertinoActivityIndicator(color: Colors.white),
                                  )
                                : const Icon(CupertinoIcons.arrow_down_doc_fill, size: 19),
                            label: Text(
                              isAr ? 'استيراد وحفظ في قاعدة البيانات' : 'Import into App DB',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _repoFilter == key,
        onSelected: (_) {
          NimoSoundFx.click();
          setState(() => _repoFilter = key);
        },
      ),
    );
  }
}

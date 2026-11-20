import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';

/// Nimo v5.0 Ultra — Mega GitHub & Public API Ingestion & Unified Knowledge Hub.
/// Every imported GitHub repo or JSON API is automatically injected into Nimo's core inverted-index DB!
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

  String? _selectedCategory;
  String _repoFilter = 'all'; // 'all' | 'apis' | 'coding' | 'ai' | 'knowledge'
  String _customCategory = 'APIs';
  bool _customIsApi = true;
  bool _isSyncingAll = false;
  bool _isAddingCustom = false;
  List<LocalDbRecord> _unifiedHits = [];

  static const Map<String, String> _catLabelsAr = {
    'github_apis': 'مستودعات APIs (محقونة)',
    'github_coding': 'برمجة GitHub (محقونة)',
    'github_ai_prompts': 'أوامر AI (محقونة)',
    'github_arabic_tech': 'تقنية عربية (محقونة)',
    'github_world_data': 'دول العالم (محقونة)',
    'github_custom_github': 'روابط مخصصة (محقونة)',
    'coding': 'البرمجة',
    'code_bank': 'بنك الأكواد',
    'code_recipes': 'وصفات كود',
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
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _customTitleCtrl.dispose();
    _customUrlCtrl.dispose();
    super.dispose();
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
              ? (isAr
                  ? 'تم استيراد البيانات وحقنها في قاعدة بيانات التطبيق بنجاح!'
                  : 'Imported & injected into Nimo core database!')
              : (isAr
                  ? 'تعذّر تحميل الرابط — تأكد أنه رابط GitHub أو JSON API صالح.'
                  : 'Failed to fetch URL — check that it is a valid GitHub or JSON API link.'),
        ),
      ),
    );
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
        title: Text(isAr ? 'استيراد قواعد البيانات و APIs' : 'GitHub & API Mega-DB'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(
              icon: const Icon(CupertinoIcons.cloud_download_fill, size: 18),
              text: isAr ? 'المستودعات (${gh.sources.length})' : 'Repos (${gh.sources.length})',
            ),
            Tab(
              icon: const Icon(CupertinoIcons.search, size: 18),
              text: isAr ? 'البحث (${localDb.totalRecords})' : 'Search (${localDb.totalRecords})',
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
              // Unified DB Injection Hero Card
              Card(
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
                                Text(
                                  isAr
                                      ? '${localDb.totalRecords} سجل محقون ومفهرس في التطبيق'
                                      : '${localDb.totalRecords} Unified Indexed Records',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isAr
                                      ? '${localDb.builtInRecords} مدمج + ${localDb.injectedRecords} محقون من ${localDb.injectedSourcesCount} مستودع GitHub/API'
                                      : '${localDb.builtInRecords} built-in + ${localDb.injectedRecords} injected from ${localDb.injectedSourcesCount} repos',
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
                                  ? 'حقن البيانات المستوردة تلقائياً في عقل Nimo والردود'
                                  : 'Auto-inject imported data into Nimo AI Brain (RAG)',
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
                                isAr ? 'حقن مستودعات APIs' : 'Inject All APIs',
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

              // Filter Chips
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

              // Repositories List
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
                                  label: isAr ? 'محقون في التطبيق • $count سجل' : 'Injected • $count records',
                                  color: TalkoraColors.iosGreen,
                                  icon: CupertinoIcons.checkmark_seal_fill,
                                )
                              else
                                IosStatusPill(
                                  label: src.isApiRepo ? 'API Repo • ${src.format.toUpperCase()}' : src.format.toUpperCase(),
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
                                            ? (isAr ? 'تحديث الحقن' : 'Refresh')
                                            : (isAr ? 'استيراد وحقن' : 'Import & Inject'),
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

          // ================= TAB 2: UNIFIED INSTANT SEARCH (<3ms) =================
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _runSearch,
                decoration: InputDecoration(
                  hintText: isAr
                      ? 'ابحث فورياً داخل ${localDb.totalRecords} سجل (مدمج + محقون من GitHub و APIs)...'
                      : 'Instant search across ${localDb.totalRecords} unified records...',
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
                header: isAr ? 'استيراد وحقن رابط GitHub أو REST API مخصص' : 'IMPORT CUSTOM GITHUB OR JSON API',
                footer: isAr
                    ? 'يدعم روابط مستودعات GitHub الكاملة، وملفات JSON / JSONL / CSV / MD / TXT، وأي رابط REST API عام يعيد JSON! يتم حقن البيانات فوراً داخل قاعدة بيانات التطبيق.'
                    : 'Supports GitHub repo URLs, raw JSON/JSONL/CSV/MD/TXT files, and live public JSON REST APIs. Automatically injected into Nimo DB.',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _customTitleCtrl,
                          decoration: InputDecoration(
                            labelText: isAr ? 'اسم قاعدة البيانات أو المستودع' : 'Dataset / API Name',
                            hintText: isAr ? 'مثال: قاعدة بيانات برمجة Flutter أو API طقس' : 'e.g. Flutter Docs or Public API',
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
                              isAr ? 'تصنيف كمستودع API / Endpoint' : 'Mark as API Repository',
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
                              isAr ? 'استيراد وحقن في بيانات التطبيق' : 'Import & Inject into App DB',
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

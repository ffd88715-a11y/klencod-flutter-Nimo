import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/ai_tool_executor.dart';
import 'package:talkora_ai/core/ai/image_gen_service.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_animations.dart';
import 'package:talkora_ai/core/widgets/nimo_chat_bubble.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';
import 'package:talkora_ai/features/coding_lab/coding_lab_screen.dart';

class _TutorPersona {
  final String id;
  final String nameEn;
  final String nameAr;
  final IconData icon;
  final Color color;
  final String prompt;

  const _TutorPersona({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.icon,
    required this.color,
    required this.prompt,
  });
}

class _PromptTemplate {
  final String titleAr;
  final String titleEn;
  final String promptAr;
  final String promptEn;
  final IconData icon;
  final Color color;

  const _PromptTemplate({
    required this.titleAr,
    required this.titleEn,
    required this.promptAr,
    required this.promptEn,
    required this.icon,
    required this.color,
  });
}

class _ChatSession {
  final String id;
  String title;
  final List<AiChatMessage> messages;

  _ChatSession({required this.id, required this.title, required this.messages});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory _ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMsgs = (json['messages'] as List<dynamic>?) ?? const [];
    return _ChatSession(
      id: (json['id'] ?? 'default').toString(),
      title: (json['title'] ?? 'محادثة جديدة').toString(),
      messages: [
        for (final item in rawMsgs)
          if (item is Map<String, dynamic>) AiChatMessage.fromJson(item),
      ],
    );
  }
}

/// Nimo v8.0 Quantum — Live SSE Streaming AI Chat Studio with Stop Generation,
/// Multi-Session History, Pro Prompt Library, In-Chat Search & Self-Healing Model Persistence.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  static const _kSessionsKey = 'nimo_ai_chat_sessions_v7';
  static const _kLegacyHistoryKey = 'nimo_ai_chat_history_v4';

  static const List<_TutorPersona> _personas = [
    _TutorPersona(
      id: 'general',
      nameEn: 'Nimo Quantum',
      nameAr: 'نيمو الخارق',
      icon: CupertinoIcons.sparkles,
      color: TalkoraColors.iosBlue,
      prompt:
          'You are Nimo v8.0 Quantum developed by YOSSEF JOO. You are an ultra-intelligent, thorough, accurate assistant powered by a unified knowledge base and GitHub/API datasets. Answer deeply, clearly, and practically in the user language (Arabic or English). Format code in fenced code blocks.',
    ),
    _TutorPersona(
      id: 'coder',
      nameEn: 'Senior Coder',
      nameAr: 'مبرمج خبير',
      icon: CupertinoIcons.chevron_left_slash_chevron_right,
      color: TalkoraColors.iosIndigo,
      prompt:
          'You are Nimo Principal Software Architect (Flutter, Dart, HTML/CSS/JS, Python, Kotlin, SQL, PHP, AI). Write complete, clean, bug-free, copy-ready code inside fenced code blocks with concise explanations.',
    ),
    _TutorPersona(
      id: 'commander',
      nameEn: 'Phone Commander',
      nameAr: 'مدير الهاتف',
      icon: CupertinoIcons.device_phone_portrait,
      color: TalkoraColors.iosGreen,
      prompt:
          'You are Nimo Phone Commander. Help the user manage their Android phone, open apps, send WhatsApp, set alarms/timers, control flashlight, navigate Maps, and search YouTube.',
    ),
    _TutorPersona(
      id: 'coach',
      nameEn: 'English Coach',
      nameAr: 'مدرب الإنجليزية',
      icon: CupertinoIcons.chat_bubble_2_fill,
      color: TalkoraColors.iosTeal,
      prompt:
          'You are Nimo English Coach. Reply naturally in English, gently correct any grammar mistake, and include a concise Arabic translation when helpful.',
    ),
    _TutorPersona(
      id: 'ielts',
      nameEn: 'IELTS Examiner',
      nameAr: 'ممتحن IELTS',
      icon: CupertinoIcons.rosette,
      color: TalkoraColors.iosPurple,
      prompt:
          'You are an official IELTS Speaking & Writing Examiner. Evaluate the user message with an estimated Band score (1-9), highlight vocabulary upgrades, and ask the next follow-up question.',
    ),
    _TutorPersona(
      id: 'business',
      nameEn: 'Business Pro',
      nameAr: 'خبير أعمال',
      icon: CupertinoIcons.briefcase_fill,
      color: TalkoraColors.iosOrange,
      prompt:
          'You are an executive business strategist, marketing director, and startup advisor. Provide actionable, sharp strategies.',
    ),
    _TutorPersona(
      id: 'creative',
      nameEn: 'Creative Studio',
      nameAr: 'كاتب ومبدع',
      icon: CupertinoIcons.paintbrush_fill,
      color: TalkoraColors.iosRed,
      prompt:
          'You are a master creative writer, storyteller, and AI image prompt designer. Craft vivid stories, scripts, and image prompts.',
    ),
  ];

  static const List<_PromptTemplate> _promptTemplates = [
    _PromptTemplate(
      titleAr: 'بناء تطبيق أو صفحة كاملة',
      titleEn: 'Build Full App / Web Page',
      promptAr: 'اكتب لي كوداً كاملاً ونظيفاً جاهزاً للتشغيل لـ: ',
      promptEn: 'Write complete, production-ready code for: ',
      icon: CupertinoIcons.chevron_left_slash_chevron_right,
      color: TalkoraColors.iosIndigo,
    ),
    _PromptTemplate(
      titleAr: 'تلخيص فائق بالنقاط',
      titleEn: 'Executive Bullet Summary',
      promptAr: 'لخّص لي النص التالي في أهم النقاط العملية بشكل منظم وواضح:\n',
      promptEn: 'Summarize the following into clear, actionable bullet points:\n',
      icon: CupertinoIcons.doc_text_fill,
      color: TalkoraColors.iosBlue,
    ),
    _PromptTemplate(
      titleAr: 'مصحح ومسرّع الأكواد',
      titleEn: 'Bug Fixer & Optimizer',
      promptAr: 'افحص الكود التالي وأصلح كل الأخطاء واجعله أسرع وأنظف:\n',
      promptEn: 'Debug and optimize the following code for maximum performance:\n',
      icon: CupertinoIcons.wrench_fill,
      color: TalkoraColors.iosTeal,
    ),
    _PromptTemplate(
      titleAr: 'خطة جيم وتغذية مخصصة',
      titleEn: 'Custom Gym & Nutrition Plan',
      promptAr: 'صمّم لي جدول تمارين أسبوعي ونظام تغذية دقيق يناسب هدفي: ',
      promptEn: 'Design a weekly gym split and nutrition plan for my goal: ',
      icon: CupertinoIcons.flame_fill,
      color: TalkoraColors.iosOrange,
    ),
    _PromptTemplate(
      titleAr: 'كتابة إيميل أو رسالة رسمية',
      titleEn: 'Professional Email Writer',
      promptAr: 'اكتب لي رسالة رسمية احترافية ومقنعة بخصوص: ',
      promptEn: 'Write a concise, persuasive professional email about: ',
      icon: CupertinoIcons.mail_solid,
      color: TalkoraColors.iosGreen,
    ),
    _PromptTemplate(
      titleAr: 'ترجمة احترافية طبيعية',
      titleEn: 'Natural Pro Translation',
      promptAr: 'ترجم النص التالي ترجمة احترافية طبيعية مع الحفاظ على المعنى الدقيق:\n',
      promptEn: 'Translate naturally while preserving tone and precision:\n',
      icon: CupertinoIcons.globe,
      color: TalkoraColors.iosPurple,
    ),
    _PromptTemplate(
      titleAr: 'محتوى فيروسي للسوشيال ميديا',
      titleEn: 'Viral Social Media Script',
      promptAr: 'اكتب لي سكريبت فيديو قصير جذاب (Hook + محتوى + Call to Action) عن: ',
      promptEn: 'Write a high-retention short video script (Hook + Body + CTA) about: ',
      icon: CupertinoIcons.sparkles,
      color: TalkoraColors.iosPink,
    ),
    _PromptTemplate(
      titleAr: 'توليد صورة سينمائية 8K',
      titleEn: 'Generate 8K Cinematic Image',
      promptAr: 'ارسم لي ',
      promptEn: '/image ',
      icon: CupertinoIcons.photo_fill,
      color: TalkoraColors.iosRed,
    ),
  ];

  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _chatSearchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_ChatSession> _sessions = [];
  String _activeSessionId = 'default';
  String _personaId = 'general';
  bool _isSending = false;
  String _streamingPreview = '';
  CancelToken? _activeCancelToken;
  bool _showSearchBar = false;
  String _searchFilter = '';
  int _lastStreamPaintMs = 0;

  _ChatSession get _currentSession {
    if (_sessions.isEmpty) {
      _sessions.add(_ChatSession(id: 'default', title: 'المحادثة الرئيسية', messages: []));
      _activeSessionId = 'default';
    }
    return _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
  }

  List<AiChatMessage> get _messages => _currentSession.messages;

  _TutorPersona get _activePersona =>
      _personas.firstWhere((p) => p.id == _personaId, orElse: () => _personas.first);

  @override
  void initState() {
    super.initState();
    _loadSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePrefillIfAny());
  }

  void _consumePrefillIfAny() {
    if (!mounted) return;
    final prefill = ref.read(chatPrefillPromptProvider);
    if (prefill != null && prefill.trim().isNotEmpty) {
      ref.read(chatPrefillPromptProvider.notifier).state = null;
      _sendMessage(prefill);
    }
  }

  @override
  void dispose() {
    _activeCancelToken?.cancel();
    _inputCtrl.dispose();
    _chatSearchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();
      final rawSessions = prefs.getString(_kSessionsKey);
      if (rawSessions != null && rawSessions.isNotEmpty) {
        final decoded = jsonDecode(rawSessions) as List<dynamic>;
        final loaded = <_ChatSession>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            loaded.add(_ChatSession.fromJson(item));
          }
        }
        if (loaded.isNotEmpty && mounted) {
          setState(() {
            _sessions
              ..clear()
              ..addAll(loaded);
            _activeSessionId = _sessions.first.id;
          });
          return;
        }
      }
      final legacyRaw = prefs.getString(_kLegacyHistoryKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty && mounted) {
        final list = jsonDecode(legacyRaw) as List<dynamic>;
        final msgs = <AiChatMessage>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) msgs.add(AiChatMessage.fromJson(item));
        }
        setState(() {
          _sessions
            ..clear()
            ..add(_ChatSession(id: 'default', title: 'المحادثة الرئيسية', messages: msgs));
          _activeSessionId = 'default';
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSessions() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();
      final capped = _sessions.take(15).map((s) {
        final trimmed = s.messages.length > 60 ? s.messages.sublist(s.messages.length - 60) : s.messages;
        return _ChatSession(id: s.id, title: s.title, messages: trimmed).toJson();
      }).toList();
      await prefs.setString(_kSessionsKey, jsonEncode(capped));
    } catch (_) {}
  }

  void _createNewSession(bool isAr) {
    NimoSoundFx.pop();
    final id = 'chat_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _sessions.insert(
        0,
        _ChatSession(
          id: id,
          title: isAr ? 'محادثة جديدة' : 'New Chat',
          messages: [],
        ),
      );
      _activeSessionId = id;
    });
    _saveSessions();
  }

  void _stopGeneration() {
    _activeCancelToken?.cancel('User stopped generation');
    _activeCancelToken = null;
    if (_streamingPreview.trim().isNotEmpty) {
      final partial = _streamingPreview.trim();
      setState(() {
        _currentSession.messages.add(
          AiChatMessage(
            role: 'assistant',
            content: partial,
            timestamp: DateTime.now(),
            modelUsed: 'Nimo (Stopped)',
          ),
        );
        _streamingPreview = '';
        _isSending = false;
      });
      _saveSessions();
    } else {
      setState(() {
        _streamingPreview = '';
        _isSending = false;
      });
    }
  }

  void _showPromptStudioSheet(bool isAr) {
    NimoSoundFx.click();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            Text(
              isAr ? 'مكتبة الأوامر الاحترافية' : 'Pro Prompt Studio',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (final tpl in _promptTemplates)
              ListTile(
                leading: IosIconBadge(icon: tpl.icon, color: tpl.color, size: 34),
                title: Text(isAr ? tpl.titleAr : tpl.titleEn, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  isAr ? tpl.promptAr.trim() : tpl.promptEn.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  NimoSoundFx.click();
                  Navigator.pop(ctx);
                  final txt = isAr ? tpl.promptAr : tpl.promptEn;
                  _inputCtrl.text = txt;
                  _inputCtrl.selection = TextSelection.fromPosition(TextPosition(offset: txt.length));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSessionsSheet(bool isAr) {
    NimoSoundFx.click();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAr ? 'المحادثات (${_sessions.length})' : 'Conversations (${_sessions.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _createNewSession(isAr);
                  },
                  icon: const Icon(CupertinoIcons.add, size: 16),
                  label: Text(isAr ? 'جديدة' : 'New'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final s in _sessions)
              ListTile(
                leading: IosIconBadge(
                  icon: CupertinoIcons.chat_bubble_text_fill,
                  color: s.id == _activeSessionId ? Theme.of(context).colorScheme.primary : TalkoraColors.iosIndigo,
                  size: 34,
                ),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(isAr ? '${s.messages.length} رسالة' : '${s.messages.length} messages'),
                trailing: _sessions.length > 1
                    ? IconButton(
                        icon: const Icon(CupertinoIcons.trash, size: 18, color: TalkoraColors.iosRed),
                        onPressed: () {
                          setState(() {
                            _sessions.removeWhere((x) => x.id == s.id);
                            if (_activeSessionId == s.id && _sessions.isNotEmpty) {
                              _activeSessionId = _sessions.first.id;
                            }
                          });
                          _saveSessions();
                          Navigator.pop(ctx);
                        },
                      )
                    : null,
                onTap: () {
                  NimoSoundFx.click();
                  setState(() => _activeSessionId = s.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (instant) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        } else {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isSending) return;

    NimoSoundFx.pop();
    _inputCtrl.clear();
    final session = _currentSession;
    if (session.messages.isEmpty) {
      session.title = text.length > 34 ? '${text.substring(0, 34)}...' : text;
    }

    final userMsg = AiChatMessage(role: 'user', content: text, timestamp: DateTime.now());
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    setState(() {
      session.messages.add(userMsg);
      _isSending = true;
      _streamingPreview = '';
    });
    _scrollToBottom();

    final aiSettings = ref.read(aiSettingsProvider);
    final aiService = ref.read(universalAiServiceProvider);
    final bridge = ref.read(nativeBridgeProvider);
    final executor = AiToolExecutor(bridge);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';

    // 1. Direct Key-Aware Image Generation Command
    final imgSlash = RegExp(r"""^/(?:image|img|draw)\s+(.+)$""", caseSensitive: false).firstMatch(text);
    final imgAr = RegExp(r"""^(?:ارسم لي|ارسم|ولد صورة|توليد صورة|اعمل صورة)\s+(.+)$""").firstMatch(text);
    final directImgPrompt = (imgSlash?.group(1) ?? imgAr?.group(1))?.trim();
    if (directImgPrompt != null && directImgPrompt.isNotEmpty) {
      final imgRes = await ref.read(imageGenServiceProvider).generateImage(
            prompt: directImgPrompt,
            styleKey: 'realistic',
            engine: 'auto_key',
            width: 1024,
            height: 1024,
            autoEnhanceArabic: true,
            aiSettings: aiSettings,
            aiService: aiService,
          );
      if (!mounted) return;
      setState(() {
        session.messages.add(
          AiChatMessage(
            role: 'assistant',
            content: imgRes.success
                ? (isAr
                    ? 'تم توليد الصورة بنجاح عبر ${imgRes.item?.engine ?? 'Nimo Image Pro'}!'
                    : 'Image generated via ${imgRes.item?.engine ?? 'Nimo Image Pro'}!')
                : (isAr ? 'تعذّر توليد الصورة: ${imgRes.error}' : 'Image error: ${imgRes.error}'),
            timestamp: DateTime.now(),
            modelUsed: imgRes.item?.engine,
            actionBadge: imgRes.success ? (isAr ? 'توليد صورة HD' : 'HD Image Generated') : null,
            imageUrl: imgRes.item?.imageUrl,
            imageBase64: imgRes.item?.base64Bytes,
          ),
        );
        _isSending = false;
        _streamingPreview = '';
      });
      await _saveSessions();
      _scrollToBottom();
      return;
    }

    // 2. Instant local phone command
    if (aiSettings.deviceControlEnabled) {
      final instant = await executor.tryInstantLocalCommand(text, isArabic: isAr);
      if (instant != null && mounted) {
        setState(() {
          session.messages.add(
            AiChatMessage(
              role: 'assistant',
              content: instant.cleanReply,
              timestamp: DateTime.now(),
              modelUsed: 'Nimo Instant Engine',
              actionBadge: instant.actionBadge,
              imageUrl: instant.generatedImageUrl,
            ),
          );
          _isSending = false;
          _streamingPreview = '';
        });
        await _saveSessions();
        _scrollToBottom();
        return;
      }
    }

    // 3. Build unified RAG context
    final ghState = ref.read(githubKnowledgeProvider);
    final unifiedRag = ghState.ragEnabled
        ? ref.read(nimoLocalDbProvider.notifier).buildOfflineRagContext(text, limit: 5)
        : '';
    final ghRag = ghState.ragEnabled
        ? ref.read(githubKnowledgeProvider.notifier).buildRagContext(text)
        : '';
    final combinedRag = '$unifiedRag$ghRag';

    final sysPrompt = StringBuffer(_activePersona.prompt);
    if (aiSettings.deviceControlEnabled) {
      sysPrompt.writeln('\n${AiToolExecutor.systemToolPrompt}');
    }

    final recentContext = session.messages.length > 18
        ? session.messages.sublist(session.messages.length - 18)
        : session.messages;

    // 4. REAL-TIME LIVE STREAMING CALL (throttled UI paint every 45ms for 120fps smoothness!)
    final result = await aiService.streamChat(
      settings: aiSettings,
      messages: recentContext,
      systemPromptOverride: sysPrompt.toString(),
      ragContext: combinedRag,
      cancelToken: cancelToken,
      onToken: (accumulated) {
        if (!mounted || cancelToken.isCancelled) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastStreamPaintMs >= 45) {
          _lastStreamPaintMs = now;
          setState(() => _streamingPreview = accumulated);
          _scrollToBottom(instant: true);
        }
      },
    );

    if (!mounted || cancelToken.isCancelled) return;
    _activeCancelToken = null;

    // Auto-persist self-healed working model on active provider!
    if (result.success &&
        !result.usedFallback &&
        result.providerId == aiSettings.activeProviderId &&
        result.modelName.isNotEmpty &&
        result.modelName != aiSettings.activeModel) {
      final cred = aiSettings.credentialFor(aiSettings.activeProviderId);
      ref.read(aiSettingsProvider.notifier).saveProviderConfig(
            providerId: aiSettings.activeProviderId,
            apiKey: cred.apiKey,
            model: result.modelName,
            baseUrl: cred.baseUrl,
            makeActive: false,
          );
    }

    String replyText;
    String? actionBadge;
    String? imageUrl;
    String? modelBadge;

    if (result.success) {
      final outcome = aiSettings.deviceControlEnabled
          ? await executor.executeAiTags(result.text, isArabic: isAr)
          : ToolExecutionOutcome(cleanReply: result.text);
      replyText = outcome.cleanReply;
      actionBadge = outcome.actionBadge ??
          (combinedRag.isNotEmpty
              ? (isAr ? 'مدعوم بقاعدة بيانات Nimo' : 'Nimo Knowledge RAG')
              : null);
      imageUrl = outcome.generatedImageUrl;
      modelBadge = '${result.providerName} • ${result.modelName} (${result.latencyMs}ms)';
      ref.read(learnerProfileProvider.notifier).addXp(10);
    } else {
      final offlineHits = ref.read(nimoLocalDbProvider.notifier).search(text, limit: 4);
      if (offlineHits.isNotEmpty) {
        final buf = StringBuffer(
          isAr
              ? 'إجابة فورية من قاعدة بيانات Nimo (${ref.read(nimoLocalDbProvider).totalRecords} سجل):\n\n'
              : 'Instant answer from Nimo Offline DB:\n\n',
        );
        for (final h in offlineHits) {
          buf.writeln('**${h.title}**\n${h.body}\n');
        }
        replyText = buf.toString().trim();
        actionBadge = isAr ? 'ذكاء محلي فوري (أوفلاين)' : 'Instant Offline DB';
        modelBadge = 'Nimo Local Engine';
      } else if (result.error == 'MISSING_API_KEY') {
        replyText = isAr
            ? 'لم تقم بإضافة مفتاح API لـ ${aiSettings.activePreset.name} بعد. اضغط على أيقونة الإعدادات بالأعلى للصق مفتاحك أو اختيار Nimo Free Cloud AI.'
            : 'No API key for ${aiSettings.activePreset.name}. Tap Settings above to paste your key or switch to Nimo Free Cloud AI.';
      } else {
        replyText = isAr
            ? 'تعذّر الاتصال بالنموذج (${result.providerName}):\n${result.error}'
            : 'Could not reach ${result.providerName}:\n${result.error}';
      }
    }

    setState(() {
      session.messages.add(
        AiChatMessage(
          role: 'assistant',
          content: replyText,
          timestamp: DateTime.now(),
          modelUsed: modelBadge,
          actionBadge: actionBadge,
          imageUrl: imageUrl,
          latencyMs: result.latencyMs,
        ),
      );
      _streamingPreview = '';
      _isSending = false;
    });
    await _saveSessions();
    _scrollToBottom();
  }

  void _regenerateAt(int assistantIdx) {
    if (_isSending || assistantIdx <= 0) return;
    final msgs = _messages;
    for (int i = assistantIdx - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        final prompt = msgs[i].content;
        setState(() => msgs.removeRange(i, msgs.length));
        _sendMessage(prompt);
        return;
      }
    }
  }

  void _exportChat() {
    if (_messages.isEmpty) return;
    NimoSoundFx.click();
    final buf = StringBuffer('=== Nimo v8.0 Quantum Chat Export ===\n\n');
    for (final m in _messages) {
      buf.writeln('${m.role == 'user' ? 'User' : 'Nimo'}: ${m.content}\n');
    }
    ref.read(nativeBridgeProvider).shareText(buf.toString(), subject: 'Nimo Conversation');
  }

  void _showQuickModelSwitcher() {
    NimoSoundFx.click();
    final ai = ref.read(aiSettingsProvider);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isAr ? 'تبديل سريع للمزود والنموذج' : 'Quick Model Switcher',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () {
                      NimoSoundFx.click();
                      Navigator.pop(ctx);
                      context.push('/settings');
                    },
                    child: Text(isAr ? 'إدارة المفاتيح' : 'Manage Keys'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...AiProviderCatalog.all.map((p) {
                final active = p.id == ai.activeProviderId;
                final hasKey = !p.requiresApiKey ||
                    AiKeySanitizer.clean(ai.credentials[p.id]?.apiKey ?? '').isNotEmpty;
                final model = ai.credentialFor(p.id).model;

                return ListTile(
                  leading: IosIconBadge(icon: p.icon, color: p.badgeColor),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(model),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasKey)
                        const Icon(CupertinoIcons.checkmark_circle_fill, color: TalkoraColors.iosGreen, size: 18),
                      if (active) ...[
                        const SizedBox(width: 8),
                        Icon(CupertinoIcons.check_mark, color: Theme.of(context).colorScheme.primary, size: 20),
                      ],
                    ],
                  ),
                  onTap: () {
                    NimoSoundFx.click();
                    ref.read(aiSettingsProvider.notifier).selectProvider(p.id);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(chatPrefillPromptProvider, (_, next) {
      if (next != null && next.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _consumePrefillIfAny());
      }
    });

    final ai = ref.watch(aiSettingsProvider);
    final gh = ref.watch(githubKnowledgeProvider);
    final localDb = ref.watch(nimoLocalDbProvider);
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalRecords = localDb.totalRecords;

    final displayedMessages = _searchFilter.isEmpty
        ? _messages
        : _messages
            .where((m) => m.content.toLowerCase().contains(_searchFilter.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: isAr ? 'المحادثات' : 'Chats',
          icon: const Icon(CupertinoIcons.square_list, size: 21),
          onPressed: () => _showSessionsSheet(isAr),
        ),
        title: GestureDetector(
          onTap: _showQuickModelSwitcher,
          child: Column(
            children: [
              Text(isAr ? 'محادثة Nimo v8.0' : 'Nimo v8.0 Studio', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              IosStatusPill(
                label: '${ai.activePreset.shortName} • ${ai.activeModel}',
                color: ai.isConfigured ? theme.colorScheme.primary : TalkoraColors.iosOrange,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: isAr ? 'بحث في المحادثة' : 'Search Chat',
            icon: Icon(_showSearchBar ? CupertinoIcons.xmark : CupertinoIcons.search, size: 19),
            onPressed: () {
              NimoSoundFx.click();
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _chatSearchCtrl.clear();
                  _searchFilter = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: isAr ? 'مشاركة المحادثة' : 'Export Chat',
            icon: const Icon(CupertinoIcons.share, size: 19),
            onPressed: _exportChat,
          ),
          IconButton(
            tooltip: isAr ? 'إعدادات المفاتيح' : 'API Settings',
            icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 20),
            onPressed: () {
              NimoSoundFx.click();
              context.push('/settings');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearchBar)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: TextField(
                controller: _chatSearchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _searchFilter = v.trim()),
                decoration: InputDecoration(
                  hintText: isAr ? 'ابحث داخل رسائل هذه المحادثة...' : 'Search messages...',
                  prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),

          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              scrollDirection: Axis.horizontal,
              itemCount: _personas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = _personas[i];
                final selected = p.id == _personaId;
                return ChoiceChip(
                  avatar: Icon(p.icon, size: 15, color: selected ? Colors.white : p.color),
                  label: Text(isAr ? p.nameAr : p.nameEn),
                  selected: selected,
                  selectedColor: p.color,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : null,
                  ),
                  onSelected: (_) {
                    NimoSoundFx.click();
                    setState(() => _personaId = p.id);
                  },
                );
              },
            ),
          ),

          SizedBox(
            height: 38,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              children: [
                ActionChip(
                  avatar: Icon(CupertinoIcons.sparkles, size: 14, color: theme.colorScheme.primary),
                  label: Text(isAr ? 'مكتبة الأوامر' : 'Prompts', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _showPromptStudioSheet(isAr),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.bolt_fill, size: 13, color: TalkoraColors.iosOrange),
                  label: Text(isAr ? 'مقارنة نموذجين' : 'AI Arena', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    NimoSoundFx.click();
                    context.push('/arena');
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(isAr ? 'تفكير عميق' : 'Deep Think', style: const TextStyle(fontSize: 11.5)),
                  selected: ai.deepThinkingEnabled,
                  onSelected: (v) {
                    NimoSoundFx.click();
                    ref.read(aiSettingsProvider.notifier).updateAdvanced(deepThinkingEnabled: v);
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(
                    isAr ? 'قاعدة Nimo ($totalRecords)' : 'DB ($totalRecords)',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: gh.ragEnabled,
                  onSelected: (v) {
                    NimoSoundFx.click();
                    ref.read(githubKnowledgeProvider.notifier).setRagEnabled(v);
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.add, size: 14),
                  label: Text(isAr ? 'محادثة جديدة' : 'New', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _createNewSession(isAr),
                ),
              ],
            ),
          ),

          Expanded(
            child: displayedMessages.isEmpty && !_isSending
                ? _EmptyStudioView(
                    persona: _activePersona,
                    isAr: isAr,
                    totalRecords: totalRecords,
                    onQuickPrompt: _sendMessage,
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    cacheExtent: 600,
                    addAutomaticKeepAlives: false,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                    itemCount: displayedMessages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isSending && index == displayedMessages.length) {
                        if (_streamingPreview.isNotEmpty) {
                          return RepaintBoundary(
                            child: NimoChatBubble(
                              message: AiChatMessage(
                                role: 'assistant',
                                content: '$_streamingPreview ▍',
                                timestamp: DateTime.now(),
                                modelUsed: '${ai.activePreset.shortName} • Live Stream',
                              ),
                              isAr: isAr,
                            ),
                          );
                        }
                        return Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? TalkoraColors.darkFill : TalkoraColors.lightFill,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                NimoThinkingWave(color: theme.colorScheme.primary),
                                const SizedBox(width: 10),
                                Text(
                                  isAr ? 'Nimo يتصل ويبث الإجابة...' : 'Nimo is streaming...',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final msg = displayedMessages[index];
                      return RepaintBoundary(
                        child: NimoChatBubble(
                          message: msg,
                          isAr: isAr,
                          onSpeak: msg.role == 'assistant'
                              ? () => ref.read(realisticTtsProvider).speakHuman(
                                    text: msg.content,
                                    aiSettings: ref.read(aiSettingsProvider),
                                  )
                              : null,
                          onRegenerate: msg.role == 'assistant' ? () => _regenerateAt(index) : null,
                          onShare: msg.role == 'assistant'
                              ? () => ref.read(nativeBridgeProvider).shareText(msg.content, subject: 'Nimo')
                              : null,
                          onOpenInCodingLab: (code, lang) {
                            ref.read(codingLabDraftProvider.notifier).state = (code: code, language: lang);
                            context.push('/coding-lab');
                          },
                        ),
                      );
                    },
                  ),
          ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface,
                border: Border(
                  top: BorderSide(
                    color: (isDark ? TalkoraColors.darkSeparator : TalkoraColors.lightSeparator)
                        .withValues(alpha: 0.45),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: isAr ? 'التحدث الصوتي' : 'Live Voice',
                    icon: Icon(CupertinoIcons.mic_circle_fill, color: theme.colorScheme.primary, size: 32),
                    onPressed: () {
                      NimoSoundFx.click();
                      context.push('/voice');
                    },
                  ),
                  IconButton(
                    tooltip: isAr ? 'لصق من الحافظة' : 'Paste',
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 22),
                    onPressed: () => NimoClipboardHelper.pasteIntoController(
                      context,
                      _inputCtrl,
                      isAr: isAr,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: isAr
                            ? 'اسأل Nimo أي شيء، أو اطلب كوداً، أو اكتب: ارسم لي...'
                            : 'Ask Nimo anything, build code, or /image ...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(42, 42),
                        backgroundColor: _isSending ? TalkoraColors.iosRed : theme.colorScheme.primary,
                        shape: const CircleBorder(),
                      ),
                      onPressed: _isSending ? _stopGeneration : _sendMessage,
                      child: Icon(
                        _isSending ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up,
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStudioView extends StatelessWidget {
  final _TutorPersona persona;
  final bool isAr;
  final int totalRecords;
  final ValueChanged<String> onQuickPrompt;

  const _EmptyStudioView({
    required this.persona,
    required this.isAr,
    required this.totalRecords,
    required this.onQuickPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final starters = isAr
        ? [
            'اكتب لي صفحة HTML و CSS احترافية لآلة حاسبة تفاعلية لأعاينها في المختبر',
            'ارسم لي مدينة مستقبلية في القاهرة وقت الغروب بدقة 8K',
            'اقترح لي أفضل APIs مجانية لبناء تطبيق ذكي',
            'ضع لي خطة عملية لزيادة الإنتاجية وتنظيم اليوم',
          ]
        : [
            'Build an interactive HTML/CSS/JS calculator page I can preview in Coding Lab',
            '/image futuristic Cairo skyline at sunset 8k cinematic',
            'Suggest the best free public APIs for building a smart mobile app',
            'Create a practical daily productivity plan',
          ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        NimoEntrance(
          child: Center(child: IosIconBadge(icon: persona.icon, color: persona.color, size: 60)),
        ),
        const SizedBox(height: 12),
        Text(
          isAr ? persona.nameAr : persona.nameEn,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          isAr
              ? 'بث حي فوري + $totalRecords سجل معرفي + نماذج 2026'
              : 'Live Streaming + $totalRecords records + 2026 AI Models',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        for (int i = 0; i < starters.length; i++)
          NimoEntrance(
            delay: Duration(milliseconds: 45 * (i + 1)),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NimoGlassTap(
                onTap: () => onQuickPrompt(starters[i]),
                child: Card(
                  child: ListTile(
                    title: Text(starters[i], style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5)),
                    trailing: Icon(CupertinoIcons.arrow_up_circle_fill, color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

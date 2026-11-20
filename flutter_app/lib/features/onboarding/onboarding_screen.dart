import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

/// Nimo v5.0 Ultra — Centered Bilingual Onboarding with Instant Auto-Detect API Key Setup.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _quickKeyCtrl = TextEditingController();
  String _level = 'B1';
  String _goal = 'Fluency';
  int _dailyMinutes = 15;
  bool _connectingKey = false;
  String? _detectedStatus;

  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  static const Map<String, String> _goalsAr = {
    'Fluency': 'الطلاقة والذكاء اليومي',
    'Coding': 'البرمجة والتطوير',
    'Work': 'العمل والأعمال',
    'Education': 'الدراسة والبحث',
    'Daily conversations': 'المحادثة الصوتية',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quickKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoConnectQuickKey() async {
    final rawKey = _quickKeyCtrl.text.trim();
    if (rawKey.isEmpty || _connectingKey) return;
    NimoSoundFx.click();
    setState(() {
      _connectingKey = true;
      _detectedStatus = null;
    });

    final detectedId = AiProviderCatalog.detectProviderFromKey(rawKey) ?? 'openai';
    final preset = AiProviderCatalog.byId(detectedId);
    final service = ref.read(universalAiServiceProvider);
    final discovery = await service.discoverLatestModel(
      providerId: detectedId,
      apiKey: rawKey,
      baseUrl: preset.defaultBaseUrl,
    );

    final chosenModel = discovery.latestModel.isNotEmpty ? discovery.latestModel : preset.defaultModel;
    await ref.read(aiSettingsProvider.notifier).saveProviderConfig(
          providerId: detectedId,
          apiKey: rawKey,
          model: chosenModel,
          baseUrl: preset.defaultBaseUrl,
        );

    if (!mounted) return;
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    setState(() {
      _connectingKey = false;
      _detectedStatus = isAr
          ? 'تم الربط تلقائياً مع ${preset.shortName} ($chosenModel)'
          : 'Auto-connected to ${preset.shortName} ($chosenModel)';
    });
  }

  Future<void> _finish() async {
    NimoSoundFx.pop();
    if (_quickKeyCtrl.text.trim().isNotEmpty && _detectedStatus == null) {
      await _autoConnectQuickKey();
    }
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    await ref.read(learnerProfileProvider.notifier).saveOnboarding(
          displayName: _nameCtrl.text.trim().isEmpty ? 'YOSSEF JOO' : _nameCtrl.text.trim(),
          nativeLanguage: isAr ? 'Arabic' : 'English',
          englishLevel: _level,
          learningGoal: _goal,
          preferredAccent: 'American',
          dailyTargetMinutes: _dailyMinutes,
          explanationLanguage: isAr ? 'Arabic' : 'English',
        );
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isAr = s.isArabic;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('onboarding_title')),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              NimoSoundFx.click();
              ref.read(learnerProfileProvider.notifier).setLocale(isAr ? 'en' : 'ar');
            },
            child: Text(isAr ? 'EN' : 'العربية'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                // Centered Welcome Header
                Column(
                  children: [
                    IosIconBadge(
                      icon: CupertinoIcons.sparkles,
                      color: accent,
                      size: 64,
                      animatedGlass: true,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isAr ? 'مرحباً بك في Nimo v5.0 Ultra' : 'Welcome to Nimo v5.0 Ultra',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAr
                          ? 'ذكاؤك الخارق، مختبر البرمجة بالمعاينة الحية، قواعد بيانات GitHub، والصوت البشري في مكان واحد.'
                          : 'Your super AI studio, live code preview lab, GitHub knowledge injection, and voice companion.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Name Input
                IosGroupedSection(
                  header: isAr ? 'بياناتك الأساسية' : 'YOUR PROFILE',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'الاسم المعروض' : 'Display Name',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              hintText: isAr ? 'مثال: يوسف' : 'e.g. Yossef',
                              prefixIcon: const Icon(CupertinoIcons.person_fill, size: 19),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isAr ? 'هدفك الأساسي' : 'Primary Focus',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _goalsAr.entries.map((entry) {
                              return ChoiceChip(
                                label: Text(isAr ? entry.value : entry.key, style: const TextStyle(fontSize: 12.5)),
                                selected: _goal == entry.key,
                                onSelected: (_) {
                                  NimoSoundFx.click();
                                  setState(() => _goal = entry.key);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isAr ? 'مستوى الإنجليزية (اختياري)' : 'English Level (CEFR)',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _levels.map((lvl) {
                              return ChoiceChip(
                                label: Text(lvl),
                                selected: _level == lvl,
                                onSelected: (_) {
                                  NimoSoundFx.click();
                                  setState(() => _level = lvl);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Optional Instant Smart API Key Auto-Connect
                IosGroupedSection(
                  header: isAr ? 'ربط سريع بمفتاح AI (اختياري)' : 'INSTANT AI KEY AUTO-CONNECT (OPTIONAL)',
                  footer: isAr
                      ? 'بمجرد لصق أي مفتاح (Gemini / OpenAI / Claude / Groq / OpenRouter / DeepSeek / xAI) يتعرف عليه التطبيق ويتصل بأحدث موديل تلقائياً. يمكنك أيضاً البدء مجاناً بدون مفتاح!'
                      : 'Paste any API key to auto-detect the provider and connect to the latest model, or skip to use Free Cloud AI.',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: TextField(
                              controller: _quickKeyCtrl,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                hintText: 'AIzaSy... / sk-... / gsk_... / sk-ant-...',
                                prefixIcon: const Icon(CupertinoIcons.lock_shield_fill, size: 19),
                                suffixIcon: IconButton(
                                  tooltip: isAr ? 'لصق' : 'Paste',
                                  icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 19),
                                  onPressed: () async {
                                    final clip = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (clip?.text != null && clip!.text!.trim().isNotEmpty) {
                                      setState(() => _quickKeyCtrl.text = clip.text!.trim());
                                      await _autoConnectQuickKey();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (_connectingKey) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CupertinoActivityIndicator(),
                                const SizedBox(width: 8),
                                Text(
                                  isAr ? 'جاري اكتشاف أحدث موديل...' : 'Discovering latest model...',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ] else if (_detectedStatus != null) ...[
                            const SizedBox(height: 10),
                            IosStatusPill(
                              label: _detectedStatus!,
                              color: TalkoraColors.iosGreen,
                              icon: CupertinoIcons.checkmark_seal_fill,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(CupertinoIcons.arrow_left_circle_fill, size: 20),
                    label: Text(
                      s.t('onboarding_cta'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

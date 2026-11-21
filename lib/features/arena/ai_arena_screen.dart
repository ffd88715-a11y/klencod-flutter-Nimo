import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_animations.dart';

/// Nimo v8.0 Quantum — AI Battle Arena (Side-by-Side Parallel Model Comparison).
/// Runs TWO AI providers/models simultaneously on the same prompt and compares speed, quality & word count!
class AiArenaScreen extends ConsumerStatefulWidget {
  const AiArenaScreen({super.key});

  @override
  ConsumerState<AiArenaScreen> createState() => _AiArenaScreenState();
}

class _AiArenaScreenState extends ConsumerState<AiArenaScreen> {
  final TextEditingController _promptCtrl = TextEditingController();
  String _providerA = 'gemini';
  String _providerB = 'pollinations';
  bool _running = false;
  AiResponseResult? _resultA;
  AiResponseResult? _resultB;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _providerA = ai.activeProviderId;
    // Pick a second distinct configured provider, or fall back to Free Cloud / Groq
    _providerB = _providerA == 'pollinations' ? 'gemini' : 'pollinations';
    for (final p in AiProviderCatalog.all) {
      if (p.id != _providerA &&
          p.id != 'ollama' &&
          AiKeySanitizer.clean(ai.credentialFor(p.id).apiKey).isNotEmpty) {
        _providerB = p.id;
        break;
      }
    }
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _runBattle() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _running) return;
    NimoSoundFx.pop();
    setState(() {
      _running = true;
      _resultA = null;
      _resultB = null;
    });

    final settings = ref.read(aiSettingsProvider);
    final service = ref.read(universalAiServiceProvider);
    final msg = [AiChatMessage(role: 'user', content: prompt, timestamp: DateTime.now())];

    final results = await Future.wait([
      service.sendChat(
        settings: settings,
        messages: msg,
        providerIdOverride: _providerA,
        allowFallback: false,
      ),
      service.sendChat(
        settings: settings,
        messages: msg,
        providerIdOverride: _providerB,
        allowFallback: false,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _resultA = results[0];
      _resultB = results[1];
      _running = false;
    });
    ref.read(learnerProfileProvider.notifier).addXp(20);
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final presetA = AiProviderCatalog.byId(_providerA);
    final presetB = AiProviderCatalog.byId(_providerB);

    final bothDone = _resultA != null && _resultB != null;
    final aFaster = bothDone &&
        _resultA!.success &&
        (!_resultB!.success || _resultA!.latencyMs <= _resultB!.latencyMs);
    final bFaster = bothDone &&
        _resultB!.success &&
        (!_resultA!.success || _resultB!.latencyMs < _resultA!.latencyMs);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'ساحة مقارنة النماذج (AI Arena)' : 'AI Battle Arena'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          NimoEntrance(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'اختر نموذجين للمقارنة المباشرة في نفس اللحظة' : 'Compare two AI engines simultaneously',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ProviderDropdown(
                            label: isAr ? 'النموذج الأول (A)' : 'Engine A',
                            value: _providerA,
                            ai: ai,
                            onChanged: (v) => setState(() => _providerA = v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              'VS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _ProviderDropdown(
                            label: isAr ? 'النموذج الثاني (B)' : 'Engine B',
                            value: _providerB,
                            ai: ai,
                            onChanged: (v) => setState(() => _providerB = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _promptCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: isAr
                            ? 'اكتب سؤالك هنا لمقارنة إجابة وسرعة النموذجين معاً...'
                            : 'Enter one prompt to benchmark both models...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _running ? null : _runBattle,
                        icon: _running
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CupertinoActivityIndicator(color: Colors.white),
                              )
                            : const Icon(CupertinoIcons.bolt_fill, size: 18),
                        label: Text(
                          _running
                              ? (isAr ? 'جاري تشغيل النموذجين بالتوازي...' : 'Running both models...')
                              : (isAr ? 'ابدأ المقارنة الآن' : 'Run Parallel Battle'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_running)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NimoThinkingWave(color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      isAr ? 'يتم اختبار ${presetA.shortName} ضد ${presetB.shortName}...' : 'Benchmarking both models...',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          if (_resultA != null)
            NimoEntrance(
              child: _ArenaResultCard(
                badge: 'A',
                preset: presetA,
                result: _resultA!,
                isWinner: aFaster,
                isAr: isAr,
                isDark: isDark,
              ),
            ),
          if (_resultB != null) ...[
            const SizedBox(height: 12),
            NimoEntrance(
              delay: const Duration(milliseconds: 70),
              child: _ArenaResultCard(
                badge: 'B',
                preset: presetB,
                result: _resultB!,
                isWinner: bFaster,
                isAr: isAr,
                isDark: isDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderDropdown extends StatelessWidget {
  final String label;
  final String value;
  final AiSettingsState ai;
  final ValueChanged<String> onChanged;

  const _ProviderDropdown({
    required this.label,
    required this.value,
    required this.ai,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: AiProviderCatalog.all
              .where((p) => p.id != 'ollama')
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(p.shortName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              NimoSoundFx.click();
              onChanged(v);
            }
          },
        ),
      ],
    );
  }
}

class _ArenaResultCard extends StatelessWidget {
  final String badge;
  final AiProviderPreset preset;
  final AiResponseResult result;
  final bool isWinner;
  final bool isAr;
  final bool isDark;

  const _ArenaResultCard({
    required this.badge,
    required this.preset,
    required this.result,
    required this.isWinner,
    required this.isAr,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = result.text.trim().isEmpty ? 0 : result.text.trim().split(RegExp(r'\s+')).length;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isWinner
              ? TalkoraColors.iosGreen.withValues(alpha: 0.7)
              : (result.success ? TalkoraColors.darkSeparator : TalkoraColors.iosRed).withValues(alpha: 0.45),
          width: isWinner ? 1.5 : 0.7,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IosIconBadge(icon: preset.icon, color: preset.badgeColor, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$badge • ${result.providerName} (${result.modelName})',
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        result.success
                            ? '${result.latencyMs} ms • $words ${isAr ? 'كلمة' : 'words'}'
                            : (isAr ? 'فشل الاتصال' : 'Failed'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: result.success ? TalkoraColors.iosGreen : TalkoraColors.iosRed,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWinner)
                  IosStatusPill(
                    label: isAr ? 'الأسرع' : 'Fastest',
                    color: TalkoraColors.iosGreen,
                    icon: CupertinoIcons.bolt_fill,
                  ),
                if (result.success)
                  IconButton(
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isAr ? 'تم نسخ الإجابة' : 'Copied answer')),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.success ? result.text : (result.error ?? 'Error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: result.success
                    ? (isDark ? TalkoraColors.darkText : TalkoraColors.lightMainText)
                    : TalkoraColors.iosRed,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

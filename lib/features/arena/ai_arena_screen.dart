import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/dual_model_fusion_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_animations.dart';

/// Nimo v9.0 OmniControl — Dual-Model Fusion & AI Battle Arena.
/// Supports 3 collaborative modes for working with TWO AI models together:
/// 1. Synergy Fusion: Runs Model A & Model B in parallel and merges both into ONE super-answer!
/// 2. Draft -> Refine Pipeline: Model A writes the first draft, Model B critiques & perfects it!
/// 3. Parallel Battle: Side-by-side comparison with 1-tap "Fuse Both Answers" button!
class AiArenaScreen extends ConsumerStatefulWidget {
  const AiArenaScreen({super.key});

  @override
  ConsumerState<AiArenaScreen> createState() => _AiArenaScreenState();
}

class _AiArenaScreenState extends ConsumerState<AiArenaScreen> {
  final TextEditingController _promptCtrl = TextEditingController();
  String _providerA = 'gemini';
  String _providerB = 'pollinations';
  String _workMode = 'synergy'; // 'synergy' | 'refine' | 'battle'
  bool _running = false;
  bool _fusingAfterBattle = false;
  String _statusMsg = '';

  AiResponseResult? _resultA;
  AiResponseResult? _resultB;
  String? _fusedAnswer;
  String? _fusionBadge;
  int _fusionLatencyMs = 0;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _providerA = ai.activeProviderId;
    _providerB = ai.fusionPartnerProviderId != _providerA
        ? ai.fusionPartnerProviderId
        : (_providerA == 'pollinations' ? 'gemini' : 'pollinations');
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

  Future<void> _runDualEngine() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _running) return;
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    NimoSoundFx.pop();
    setState(() {
      _running = true;
      _resultA = null;
      _resultB = null;
      _fusedAnswer = null;
      _fusionBadge = null;
      _statusMsg = isAr ? 'جاري تشغيل النموذجين معاً...' : 'Running both AI models...';
    });

    final settings = ref.read(aiSettingsProvider);
    final msg = [AiChatMessage(role: 'user', content: prompt, timestamp: DateTime.now())];

    if (_workMode == 'battle') {
      final service = ref.read(universalAiServiceProvider);
      final results = await Future.wait([
        service.sendChat(settings: settings, messages: msg, providerIdOverride: _providerA, allowFallback: false),
        service.sendChat(settings: settings, messages: msg, providerIdOverride: _providerB, allowFallback: false),
      ]);
      if (!mounted) return;
      setState(() {
        _resultA = results[0];
        _resultB = results[1];
        _running = false;
      });
    } else {
      final fusion = ref.read(dualModelFusionProvider);
      final res = await fusion.runDualFusion(
        settings: settings,
        messages: msg,
        providerA: _providerA,
        providerB: _providerB,
        mode: _workMode,
        isArabic: isAr,
        onStatus: (st) {
          if (mounted) setState(() => _statusMsg = st);
        },
      );
      if (!mounted) return;
      setState(() {
        _resultA = res.resultA;
        _resultB = res.resultB;
        _fusedAnswer = res.success ? res.mergedText : (res.error ?? 'Error');
        _fusionBadge = res.fusionBadge;
        _fusionLatencyMs = res.totalLatencyMs;
        _running = false;
      });
    }
    ref.read(learnerProfileProvider.notifier).addXp(25);
  }

  Future<void> _fuseExistingBattle() async {
    if (_resultA == null || _resultB == null || !_resultA!.success || !_resultB!.success || _fusingAfterBattle) {
      return;
    }
    NimoSoundFx.pop();
    setState(() => _fusingAfterBattle = true);
    final settings = ref.read(aiSettingsProvider);
    final fusion = ref.read(dualModelFusionProvider);
    final res = await fusion.fuseTwoResponses(
      settings: settings,
      originalPrompt: _promptCtrl.text.trim(),
      answerA: _resultA!.text,
      labelA: '${_resultA!.providerName} (${_resultA!.modelName})',
      answerB: _resultB!.text,
      labelB: '${_resultB!.providerName} (${_resultB!.modelName})',
      synthesizerProviderId: _providerA,
    );
    if (!mounted) return;
    setState(() {
      _fusingAfterBattle = false;
      if (res.success) {
        _fusedAnswer = res.text;
        _fusionBadge = '${_resultA!.providerName} + ${_resultB!.providerName} Fusion';
        _fusionLatencyMs = res.latencyMs;
      }
    });
  }

  Future<void> _applyToMainChat(bool isAr) async {
    NimoSoundFx.click();
    await ref.read(aiSettingsProvider.notifier).selectProvider(_providerA);
    await ref.read(aiSettingsProvider.notifier).updateAdvanced(
          dualFusionEnabled: true,
          fusionPartnerProviderId: _providerB,
          fusionMode: _workMode == 'refine' ? 'refine' : 'synergy',
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم تفعيل دمج النموذجين تلقائياً داخل المحادثة الرئيسية!'
              : 'Dual-Model Fusion is now active in your main AI Chat!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final presetA = AiProviderCatalog.byId(_providerA);
    final presetB = AiProviderCatalog.byId(_providerB);

    final bothSuccess = _resultA != null && _resultB != null && _resultA!.success && _resultB!.success;
    final aFaster = _resultA != null &&
        _resultB != null &&
        _resultA!.success &&
        (!_resultB!.success || _resultA!.latencyMs <= _resultB!.latencyMs);
    final bFaster = _resultA != null &&
        _resultB != null &&
        _resultB!.success &&
        (!_resultA!.success || _resultB!.latencyMs < _resultA!.latencyMs);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'دمج نموذجين + ساحة المقارنة' : 'Dual-Model Fusion & Arena'),
        actions: [
          TextButton.icon(
            onPressed: () => _applyToMainChat(isAr),
            icon: const Icon(CupertinoIcons.checkmark_seal_fill, size: 16),
            label: Text(isAr ? 'تفعيل بالشات' : 'Use in Chat'),
          ),
        ],
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
                      isAr ? 'ادمج نموذجين للعمل معاً على نفس السؤال' : 'Combine 2 AI Models to Work Together',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'synergy', label: Text(isAr ? 'دمج تآزري' : 'Synergy')),
                        ButtonSegment(value: 'refine', label: Text(isAr ? 'مسودة + مراجعة' : 'Draft→Refine')),
                        ButtonSegment(value: 'battle', label: Text(isAr ? 'مقارنة VS' : 'Battle VS')),
                      ],
                      selected: {_workMode},
                      onSelectionChanged: (s) {
                        NimoSoundFx.click();
                        setState(() => _workMode = s.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ProviderDropdown(
                            label: isAr ? 'النموذج الأول (A)' : 'Model A',
                            value: _providerA,
                            ai: ai,
                            onChanged: (v) => setState(() => _providerA = v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              _workMode == 'battle' ? 'VS' : (_workMode == 'refine' ? '→' : '+'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _ProviderDropdown(
                            label: isAr ? 'النموذج الثاني (B)' : 'Model B',
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
                            ? 'اكتب سؤالك أو مشروعك هنا ليعمل النموذجان معاً على إنتاجه بأعلى دقة...'
                            : 'Enter a prompt for both models to collaborate on...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _running ? null : _runDualEngine,
                        icon: _running
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CupertinoActivityIndicator(color: Colors.white),
                              )
                            : const Icon(CupertinoIcons.sparkles, size: 18),
                        label: Text(
                          _running
                              ? _statusMsg
                              : (_workMode == 'battle'
                                  ? (isAr ? 'ابدأ المقارنة الآن' : 'Run Parallel Battle')
                                  : (isAr ? 'شغّل دمج النموذجين الآن' : 'Run Dual-Model Fusion')),
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
                    Flexible(child: Text(_statusMsg, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),

          // Unified Merged Super-Answer Card
          if (_fusedAnswer != null) ...[
            NimoEntrance(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.75), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IosIconBadge(icon: CupertinoIcons.sparkles, color: theme.colorScheme.primary, size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr ? 'الإجابة المدمجة الخارقة (Dual Fusion)' : 'Merged Dual-Model Super Answer',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  '${_fusionBadge ?? ''} • ${_fusionLatencyMs} ms',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _fusedAnswer!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isAr ? 'تم نسخ الإجابة المدمجة' : 'Copied merged answer')),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _fusedAnswer!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? TalkoraColors.darkText : TalkoraColors.lightMainText,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 1-tap Fuse button when in Battle mode
          if (_workMode == 'battle' && bothSuccess && _fusedAnswer == null) ...[
            FilledButton.tonalIcon(
              onPressed: _fusingAfterBattle ? null : _fuseExistingBattle,
              icon: _fusingAfterBattle
                  ? const SizedBox(width: 15, height: 15, child: CupertinoActivityIndicator())
                  : const Icon(CupertinoIcons.sparkles, size: 17),
              label: Text(isAr ? 'ادمج الإجابتين في إجابة واحدة خارقة' : 'Fuse Both Answers Into One'),
            ),
            const SizedBox(height: 12),
          ],

          if (_resultA != null)
            NimoEntrance(
              child: _ArenaResultCard(
                badge: 'A',
                preset: presetA,
                result: _resultA!,
                isWinner: _workMode == 'battle' && aFaster,
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
                isWinner: _workMode == 'battle' && bFaster,
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

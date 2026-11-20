import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';

class _GrammarQuestion {
  final String ruleTitle;
  final String explanationAr;
  final String sentence;
  final List<String> options;
  final String correct;

  const _GrammarQuestion({
    required this.ruleTitle,
    required this.explanationAr,
    required this.sentence,
    required this.options,
    required this.correct,
  });
}

/// Nimo v6.0 Titan — Interactive AI Grammar Studio & Sentence Analyzer.
class GrammarScreen extends ConsumerStatefulWidget {
  const GrammarScreen({super.key});

  @override
  ConsumerState<GrammarScreen> createState() => _GrammarScreenState();
}

class _GrammarScreenState extends ConsumerState<GrammarScreen> {
  static const List<_GrammarQuestion> _questions = [
    _GrammarQuestion(
      ruleTitle: 'Present Perfect vs. Past Simple',
      explanationAr: 'نستخدم الماضي البسيط للأحداث المنتهية في وقت محدد، والمضارع التام (has/have + V3) للأحداث الممتدة حتى الحاضر مع since/for.',
      sentence: 'She ___ in Cairo since 2021.',
      options: ['lived', 'has lived', 'is living', 'lives'],
      correct: 'has lived',
    ),
    _GrammarQuestion(
      ruleTitle: 'Second Conditional (Unreal Present)',
      explanationAr: 'في الحالة الشرطية الثانية نستخدم: If + Past Simple -> would + infinitive للتعبير عن موقف تخيلي.',
      sentence: 'If I ___ more free time, I would learn Japanese.',
      options: ['have', 'had', 'will have', 'having'],
      correct: 'had',
    ),
    _GrammarQuestion(
      ruleTitle: 'Passive Voice (Past Simple)',
      explanationAr: 'للمبني للمجهول في الماضي البسيط نستخدم was / were + التصريف الثالث للفعل.',
      sentence: 'This Flutter app ___ built in 2026.',
      options: ['is', 'was', 'were', 'has'],
      correct: 'was',
    ),
    _GrammarQuestion(
      ruleTitle: 'Gerund after Prepositions',
      explanationAr: 'بعد حروف الجر (مثل in, on, at, about, of) يأتي الفعل دائماً بصيغة ing.',
      sentence: 'He is very good at ___ clean code.',
      options: ['write', 'wrote', 'writing', 'written'],
      correct: 'writing',
    ),
  ];

  final _customSentenceCtrl = TextEditingController();
  int _qIdx = 0;
  String? _selected;
  bool _checked = false;
  bool _isAnalyzing = false;
  String? _aiGrammarResult;

  _GrammarQuestion get _q => _questions[_qIdx];

  @override
  void dispose() {
    _customSentenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyzeCustomSentence() async {
    final txt = _customSentenceCtrl.text.trim();
    if (txt.isEmpty || _isAnalyzing) return;
    NimoSoundFx.click();
    setState(() {
      _isAnalyzing = true;
      _aiGrammarResult = null;
    });

    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    final res = await ref.read(universalAiServiceProvider).sendChat(
      settings: ref.read(aiSettingsProvider),
      systemPromptOverride:
          'You are an expert English Grammar Tutor. Analyze the user sentence: point out any grammar errors, provide the corrected natural version, and explain the exact grammar rule clearly in ${isAr ? 'Arabic' : 'English'}.',
      messages: [AiChatMessage(role: 'user', content: txt, timestamp: DateTime.now())],
    );

    if (!mounted) return;
    setState(() {
      _isAnalyzing = false;
      _aiGrammarResult = res.success ? res.text : (res.error ?? 'Connection error');
    });
    if (res.success) ref.read(learnerProfileProvider.notifier).addXp(15);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'استوديو القواعد الذكي AI' : 'AI Grammar Studio'),
        actions: [
          IconButton(
            tooltip: isAr ? 'القاعدة التالية' : 'Next Rule',
            icon: const Icon(CupertinoIcons.forward_fill),
            onPressed: () {
              NimoSoundFx.click();
              setState(() {
                _qIdx = (_qIdx + 1) % _questions.length;
                _selected = null;
                _checked = false;
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Free-Form Grammar Checker
          IosGroupedSection(
            header: isAr ? 'فحص وتصحيح أي جملة بالذكاء الاصطناعي' : 'AI INSTANT GRAMMAR CHECKER',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _customSentenceCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Write any English sentence to check grammar...',
                          suffixIcon: IconButton(
                            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                            onPressed: () => NimoClipboardHelper.pasteIntoController(
                              context,
                              _customSentenceCtrl,
                              isAr: isAr,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isAnalyzing ? null : _analyzeCustomSentence,
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CupertinoActivityIndicator(color: Colors.white),
                              )
                            : const Icon(CupertinoIcons.sparkles, size: 18),
                        label: Text(isAr ? 'فحص القواعد وشرح الأخطاء' : 'Check & Explain Grammar'),
                      ),
                    ),
                    if (_aiGrammarResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(_aiGrammarResult!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Interactive Grammar Quiz
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(_q.ruleTitle, style: theme.textTheme.titleLarge)),
                      IosStatusPill(label: '${_qIdx + 1}/${_questions.length}', color: TalkoraColors.iosIndigo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_q.explanationAr, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(_q.sentence, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  ..._q.options.map(
                    (opt) => RadioListTile<String>(
                      title: Directionality(textDirection: TextDirection.ltr, child: Text(opt)),
                      value: opt,
                      groupValue: _selected,
                      onChanged: (v) {
                        NimoSoundFx.click();
                        setState(() {
                          _selected = v;
                          _checked = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _selected == null
                              ? null
                              : () {
                                  NimoSoundFx.pop();
                                  setState(() => _checked = true);
                                  if (_selected == _q.correct) {
                                    ref.read(learnerProfileProvider.notifier).addXp(15);
                                  }
                                },
                          child: Text(isAr ? 'تحقق من الإجابة' : 'Check Answer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonal(
                        onPressed: () {
                          NimoSoundFx.click();
                          setState(() {
                            _qIdx = (_qIdx + 1) % _questions.length;
                            _selected = null;
                            _checked = false;
                          });
                        },
                        child: Text(isAr ? 'التالي' : 'Next'),
                      ),
                    ],
                  ),
                  if (_checked) ...[
                    const SizedBox(height: 12),
                    Text(
                      _selected == _q.correct
                          ? (isAr ? 'إجابة صحيحة! (+15 XP)' : 'Correct! (+15 XP)')
                          : (isAr ? 'الإجابة الصحيحة هي: "${_q.correct}"' : 'Correct answer: "${_q.correct}"'),
                      style: TextStyle(
                        color: _selected == _q.correct ? TalkoraColors.iosGreen : TalkoraColors.iosRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/permissions/mic_permission_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

/// Nimo v6.0 Titan — Real Microphone & AI Pronunciation Coach.
/// Plays native target pronunciation, listens via real Android SpeechRecognizer,
/// scores word-by-word accuracy, and gives tailored Arabic phonetic tips via AI!
class PronunciationScreen extends ConsumerStatefulWidget {
  const PronunciationScreen({super.key});

  @override
  ConsumerState<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends ConsumerState<PronunciationScreen> {
  static const List<String> _sentences = [
    'Practice makes pronunciation very clear and confident.',
    'Artificial intelligence helps developers build faster mobile apps.',
    'Could you please explain how this software architecture works?',
    'Consistency every single day creates extraordinary results.',
  ];

  final _micPermission = const MicPermissionService();
  final _spokenCtrl = TextEditingController();
  StreamSubscription<NativeVoiceEvent>? _voiceSub;

  int _idx = 0;
  bool _isListening = false;
  bool _isAnalyzingAi = false;
  double? _score;
  List<String> _tips = [];
  String? _aiCoachFeedback;

  String get _targetSentence => _sentences[_idx];

  @override
  void initState() {
    super.initState();
    _voiceSub = ref.read(nativeBridgeProvider).voiceEvents.listen((e) {
      if (!mounted) return;
      if (e.type == 'partial') {
        setState(() => _spokenCtrl.text = e.text);
      } else if (e.type == 'final') {
        setState(() {
          _isListening = false;
          if (e.text.trim().isNotEmpty) _spokenCtrl.text = e.text.trim();
        });
        if (_spokenCtrl.text.trim().isNotEmpty) _evaluate();
      } else if (e.type == 'error') {
        setState(() => _isListening = false);
      }
    });
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    _spokenCtrl.dispose();
    ref.read(nativeBridgeProvider).cancelListening();
    ref.read(realisticTtsProvider).stop();
    super.dispose();
  }

  Future<void> _listenTarget() async {
    NimoSoundFx.click();
    await ref.read(realisticTtsProvider).speakHuman(
          text: _targetSentence,
          aiSettings: ref.read(aiSettingsProvider),
          locale: 'en-US',
          rate: 0.9,
        );
  }

  Future<void> _toggleRecord() async {
    NimoSoundFx.click();
    final bridge = ref.read(nativeBridgeProvider);
    if (_isListening) {
      await bridge.stopListening();
      setState(() => _isListening = false);
      return;
    }

    final perm = await _micPermission.requestMicrophone();
    if (perm != MicPermissionResult.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى تفعيل صلاحية الميكروفون لاختبار النطق.')),
        );
      }
      return;
    }

    await ref.read(realisticTtsProvider).stop();
    setState(() {
      _isListening = true;
      _spokenCtrl.clear();
      _score = null;
      _aiCoachFeedback = null;
    });
    await bridge.startListening(locale: 'en-US');
  }

  Future<void> _evaluate() async {
    final spoken = _spokenCtrl.text.trim();
    if (spoken.isEmpty) return;

    final targetWords = _targetSentence.toLowerCase().split(RegExp(r"""\s+"""));
    final spokenWords = spoken.toLowerCase().split(RegExp(r"""\s+"""));
    int matches = 0;
    final foundTips = <String>[];
    for (int i = 0; i < targetWords.length; i++) {
      final tw = targetWords[i].replaceAll(RegExp(r"""[^a-z]"""), '');
      final sw = i < spokenWords.length ? spokenWords[i].replaceAll(RegExp(r"""[^a-z]"""), '') : '';
      if (tw == sw) {
        matches++;
      } else {
        foundTips.add('"$tw": سمعت "${sw.isEmpty ? "(ناقصة)" : sw}" — كررها ببطء وبوضوح.');
      }
    }

    final pct = (matches / targetWords.length) * 100;
    setState(() {
      _score = pct;
      _tips = foundTips;
      _isAnalyzingAi = true;
    });
    if (pct >= 75) ref.read(learnerProfileProvider.notifier).addXp(25);

    // Real AI Phonetic Coaching
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    final res = await ref.read(universalAiServiceProvider).sendChat(
      settings: ref.read(aiSettingsProvider),
      systemPromptOverride:
          'You are an expert English pronunciation coach. Compare the target sentence and what the learner actually spoke, and give 2-3 short, practical phonetic tips in ${isAr ? 'Arabic' : 'English'}.',
      messages: [
        AiChatMessage(
          role: 'user',
          content: 'Target: "$_targetSentence"\nLearner spoke: "$spoken"\nScore: ${pct.toStringAsFixed(0)}%',
          timestamp: DateTime.now(),
        ),
      ],
    );
    if (mounted) {
      setState(() {
        _isAnalyzingAi = false;
        if (res.success) _aiCoachFeedback = res.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'مدرب النطق الذكي AI' : 'AI Pronunciation Coach'),
        actions: [
          IconButton(
            tooltip: isAr ? 'الجملة التالية' : 'Next Sentence',
            icon: const Icon(CupertinoIcons.forward_fill),
            onPressed: () {
              NimoSoundFx.click();
              setState(() {
                _idx = (_idx + 1) % _sentences.length;
                _spokenCtrl.clear();
                _score = null;
                _aiCoachFeedback = null;
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isAr ? 'الجملة المستهدفة' : 'Target Sentence', style: theme.textTheme.labelLarge),
                      IosStatusPill(label: '${_idx + 1}/${_sentences.length}', color: TalkoraColors.iosBlue),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(_targetSentence, style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _listenTarget,
                          icon: const Icon(CupertinoIcons.speaker_2_fill, size: 18),
                          label: Text(isAr ? 'اسمع النطق الصحيح' : 'Hear Native'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _isListening ? TalkoraColors.iosRed : TalkoraColors.iosGreen,
                          ),
                          onPressed: _toggleRecord,
                          icon: Icon(_isListening ? CupertinoIcons.stop_circle : CupertinoIcons.mic_fill, size: 18),
                          label: Text(_isListening
                              ? (isAr ? 'جاري الاستماع...' : 'Listening...')
                              : (isAr ? 'انطق الآن' : 'Speak Now')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _spokenCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: isAr ? 'ما تم التقاطه من صوتك' : 'Captured Speech',
                hintText: 'Tap "Speak Now" and read the sentence aloud...',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _evaluate,
            icon: const Icon(CupertinoIcons.waveform_path_ecg, size: 19),
            label: Text(isAr ? 'تحليل وتقييم النطق بالذكاء الاصطناعي' : 'Analyze Pronunciation with AI'),
          ),

          if (_score != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'دقة النطق: ${_score!.toStringAsFixed(0)}%' : 'Accuracy: ${_score!.toStringAsFixed(0)}%',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: _score! >= 75 ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_tips.isEmpty)
                      Text(
                        isAr ? 'نطق ممتاز وواضح في جميع الكلمات!' : 'Clear articulation across every word!',
                        style: const TextStyle(color: TalkoraColors.iosGreen, fontWeight: FontWeight.w600),
                      )
                    else
                      ..._tips.map((t) => Padding(padding: const EdgeInsets.only(top: 5), child: Text('• $t'))),
                    if (_isAnalyzingAi) ...[
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          CupertinoActivityIndicator(),
                          SizedBox(width: 8),
                          Text('جاري تحليل النطق بالذكاء الاصطناعي...'),
                        ],
                      ),
                    ] else if (_aiCoachFeedback != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(_aiCoachFeedback!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

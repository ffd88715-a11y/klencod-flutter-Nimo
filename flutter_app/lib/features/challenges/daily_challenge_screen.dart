import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

/// Nimo v6.0 Titan — Interactive Daily AI Challenge with Live Countdown Timer,
/// Dynamic AI Prompts & Real-Time Fluency/Logic Evaluation!
class DailyChallengeScreen extends ConsumerStatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  ConsumerState<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends ConsumerState<DailyChallengeScreen> {
  static const List<({String title, String task})> _challenges = [
    (
      title: 'Describe Your Ideal Productive Morning',
      task: 'Write or speak for 90 seconds using sequence words (first, after that, finally) and one future goal.',
    ),
    (
      title: 'Pitch Your Favorite App Idea in 60 Seconds',
      task: 'Explain what problem your app solves, who uses it, and why it stands out.',
    ),
    (
      title: 'Explain AI to a 10-Year-Old',
      task: 'Use simple, vivid analogies and everyday examples with clear structure.',
    ),
  ];

  final _answerCtrl = TextEditingController();
  int _idx = 0;
  int _secondsLeft = 90;
  Timer? _timer;
  bool _running = false;
  bool _evaluating = false;
  String? _aiEvaluation;

  @override
  void dispose() {
    _timer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    NimoSoundFx.click();
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_secondsLeft <= 0) _secondsLeft = 90;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() {
          _secondsLeft = 0;
          _running = false;
        });
        NimoSoundFx.chime();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _evaluateSubmission() async {
    final text = _answerCtrl.text.trim();
    if (text.isEmpty || _evaluating) return;
    NimoSoundFx.pop();
    _timer?.cancel();
    setState(() {
      _running = false;
      _evaluating = true;
      _aiEvaluation = null;
    });

    final ch = _challenges[_idx];
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    final res = await ref.read(universalAiServiceProvider).sendChat(
      settings: ref.read(aiSettingsProvider),
      systemPromptOverride:
          'Evaluate the user response to this daily challenge: "${ch.title} — ${ch.task}". '
          'Give a score out of 10, highlight 2 strengths, and 2 quick upgrades in ${isAr ? 'Arabic' : 'English'}.',
      messages: [AiChatMessage(role: 'user', content: text, timestamp: DateTime.now())],
    );

    if (!mounted) return;
    setState(() {
      _evaluating = false;
      _aiEvaluation = res.success ? res.text : (res.error ?? 'Connection error');
    });
    if (res.success) {
      ref.read(learnerProfileProvider.notifier).incrementSpeakingMinutes(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final ch = _challenges[_idx];

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'التحدي اليومي الذكي' : 'Daily AI Challenge'),
        actions: [
          IconButton(
            tooltip: isAr ? 'تحدي آخر' : 'Next Challenge',
            icon: const Icon(CupertinoIcons.refresh),
            onPressed: () {
              NimoSoundFx.click();
              _timer?.cancel();
              setState(() {
                _idx = (_idx + 1) % _challenges.length;
                _secondsLeft = 90;
                _running = false;
                _aiEvaluation = null;
                _answerCtrl.clear();
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
                      IosStatusPill(
                        label: '${_secondsLeft}s ${isAr ? 'متبقي' : 'left'}',
                        color: _secondsLeft < 20 ? TalkoraColors.iosRed : TalkoraColors.iosBlue,
                        icon: CupertinoIcons.timer,
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _toggleTimer,
                        icon: Icon(_running ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 16),
                        label: Text(_running ? (isAr ? 'إيقاف' : 'Pause') : (isAr ? 'ابدأ المؤقت' : 'Start Timer')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ch.title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(ch.task, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _answerCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: isAr
                  ? 'اكتب إجابتك هنا ليقيّمها Nimo ويعطيك درجة من 10...'
                  : 'Write your challenge response here for AI scoring...',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _evaluating ? null : _evaluateSubmission,
                  icon: _evaluating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CupertinoActivityIndicator(color: Colors.white),
                        )
                      : const Icon(CupertinoIcons.checkmark_seal_fill, size: 18),
                  label: Text(isAr ? 'تقييم بالذكاء الاصطناعي' : 'Evaluate with AI'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: () => context.push('/voice'),
                icon: const Icon(CupertinoIcons.mic_fill, size: 18),
                label: Text(isAr ? 'تحدث صوتياً' : 'Speak Live'),
              ),
            ],
          ),
          if (_aiEvaluation != null) ...[
            const SizedBox(height: 16),
            IosGroupedSection(
              header: isAr ? 'تقييم Nimo للتحدي' : 'NIMO AI EVALUATION',
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(_aiEvaluation!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

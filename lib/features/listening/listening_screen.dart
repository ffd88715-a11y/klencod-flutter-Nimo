import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

class _ListeningLesson {
  final String title;
  final String level;
  final String script;
  final String question;
  final List<String> options;
  final String correctAnswer;

  const _ListeningLesson({
    required this.title,
    required this.level,
    required this.script,
    required this.question,
    required this.options,
    required this.correctAnswer,
  });
}

/// Nimo v6.0 Titan — REAL Audio Listening Lab with Live Human TTS Playback,
/// Speed Controls, Built-In Multi-Level Lessons & Unlimited AI Lesson Generation!
class ListeningScreen extends ConsumerStatefulWidget {
  const ListeningScreen({super.key});

  @override
  ConsumerState<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends ConsumerState<ListeningScreen> {
  static const List<_ListeningLesson> _builtIn = [
    _ListeningLesson(
      title: 'Ordering Coffee in London',
      level: 'A2 • British',
      script:
          'Barista: Good morning! What can I get started for you today? Customer: Hi there, could I have a medium flat white with oat milk, please? Barista: Of course. To have here or to take away? Customer: To take away, thanks.',
      question: 'What kind of milk does the customer order?',
      options: ['Whole milk', 'Oat milk', 'Soy milk'],
      correctAnswer: 'Oat milk',
    ),
    _ListeningLesson(
      title: 'Tech Startup Job Interview',
      level: 'B2 • American',
      script:
          'Interviewer: Tell me about a tough bug you solved recently. Candidate: Last month our mobile app crashed on slow networks. I added local caching and automatic retry logic, which cut crash reports by eighty percent.',
      question: 'How did the candidate fix the mobile app crashes?',
      options: ['Deleted all user data', 'Added local caching and retry logic', 'Changed the app logo'],
      correctAnswer: 'Added local caching and retry logic',
    ),
    _ListeningLesson(
      title: 'Airport Gate Announcement',
      level: 'B1 • International',
      script:
          'Attention passengers on flight 408 to Dubai. Boarding will begin in fifteen minutes at Gate 14B. Please have your boarding pass and passport ready for inspection.',
      question: 'Which gate is flight 408 boarding from?',
      options: ['Gate 4A', 'Gate 14B', 'Gate 24C'],
      correctAnswer: 'Gate 14B',
    ),
  ];

  int _lessonIdx = 0;
  _ListeningLesson? _aiLesson;
  bool _showTranscript = false;
  bool _isPlaying = false;
  bool _isGenerating = false;
  double _rate = 0.95;
  String? _answer;

  _ListeningLesson get _current => _aiLesson ?? _builtIn[_lessonIdx];

  @override
  void dispose() {
    ref.read(realisticTtsProvider).stop();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    NimoSoundFx.click();
    final tts = ref.read(realisticTtsProvider);
    if (_isPlaying) {
      await tts.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    final aiSettings = ref.read(aiSettingsProvider);
    await tts.speakHuman(
      text: _current.script,
      aiSettings: aiSettings,
      locale: 'en-US',
      rate: _rate,
      onStart: () {
        if (mounted) setState(() => _isPlaying = true);
      },
      onDone: () {
        if (mounted) setState(() => _isPlaying = false);
      },
    );
  }

  Future<void> _generateAiLesson() async {
    if (_isGenerating) return;
    NimoSoundFx.click();
    await ref.read(realisticTtsProvider).stop();
    setState(() {
      _isGenerating = true;
      _isPlaying = false;
      _answer = null;
      _showTranscript = false;
    });

    final level = ref.read(learnerProfileProvider).englishLevel;
    final ai = ref.read(aiSettingsProvider);
    final res = await ref.read(universalAiServiceProvider).sendChat(
      settings: ai,
      systemPromptOverride:
          'Generate a short realistic English listening dialogue for CEFR level $level. '
          'Return ONLY valid JSON with keys: "title", "script" (4-5 natural spoken sentences), "question", "options" (array of 3 choices), "correctAnswer" (must match one option exactly). No markdown.',
      messages: [AiChatMessage(role: 'user', content: 'Create a fresh listening exercise.', timestamp: DateTime.now())],
    );

    if (!mounted) return;
    if (res.success) {
      try {
        var raw = res.text.trim();
        final m = RegExp(r"""\{[\s\S]*\}""").firstMatch(raw);
        if (m != null) raw = m.group(0)!;
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final opts = (j['options'] as List<dynamic>).map((e) => e.toString()).toList();
        if (opts.length >= 2) {
          setState(() {
            _aiLesson = _ListeningLesson(
              title: (j['title'] ?? 'AI Listening Lesson').toString(),
              level: 'AI • $level',
              script: (j['script'] ?? '').toString(),
              question: (j['question'] ?? '').toString(),
              options: opts,
              correctAnswer: (j['correctAnswer'] ?? opts.first).toString(),
            );
            _isGenerating = false;
          });
          return;
        }
      } catch (_) {}
    }

    setState(() {
      _isGenerating = false;
      _aiLesson = null;
      _lessonIdx = (_lessonIdx + 1) % _builtIn.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final lesson = _current;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'مختبر الاستماع الصوتي AI' : 'AI Listening Lab'),
        actions: [
          IconButton(
            tooltip: isAr ? 'درس جديد بالذكاء الاصطناعي' : 'Generate AI Lesson',
            icon: _isGenerating
                ? const SizedBox(width: 18, height: 18, child: CupertinoActivityIndicator())
                : const Icon(CupertinoIcons.sparkles),
            onPressed: _generateAiLesson,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Lesson Switcher
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _builtIn.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(_builtIn[i].title, style: const TextStyle(fontSize: 12)),
                      selected: _aiLesson == null && _lessonIdx == i,
                      onSelected: (_) {
                        ref.read(realisticTtsProvider).stop();
                        setState(() {
                          _aiLesson = null;
                          _lessonIdx = i;
                          _isPlaying = false;
                          _answer = null;
                        });
                      },
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.sparkles, size: 15),
                  label: Text(isAr ? 'توليد درس AI جديد' : 'New AI Lesson', style: const TextStyle(fontSize: 12)),
                  onPressed: _generateAiLesson,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(lesson.title, style: theme.textTheme.titleLarge)),
                      IosStatusPill(label: lesson.level, color: TalkoraColors.iosBlue),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _togglePlay,
                          icon: Icon(_isPlaying ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill, size: 18),
                          label: Text(_isPlaying
                              ? (isAr ? 'إيقاف الصوت' : 'Stop Audio')
                              : (isAr ? 'تشغيل الدرس صوتياً' : 'Play Audio Lesson')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => setState(() => _showTranscript = !_showTranscript),
                        child: Text(_showTranscript
                            ? (isAr ? 'إخفاء النص' : 'Hide Text')
                            : (isAr ? 'إظهار النص' : 'Show Text')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(isAr ? 'السرعة:' : 'Speed:', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: CupertinoSlider(
                          value: _rate,
                          min: 0.7,
                          max: 1.3,
                          divisions: 6,
                          onChanged: (v) => setState(() => _rate = v),
                        ),
                      ),
                      Text('${_rate.toStringAsFixed(2)}x', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  if (_showTranscript) ...[
                    const SizedBox(height: 10),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(lesson.script, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isAr ? 'اختبار الفهم السماعي' : 'Comprehension Check', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(lesson.question, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  ...lesson.options.map(
                    (opt) => RadioListTile<String>(
                      title: Directionality(textDirection: TextDirection.ltr, child: Text(opt)),
                      value: opt,
                      groupValue: _answer,
                      onChanged: (v) {
                        NimoSoundFx.click();
                        setState(() => _answer = v);
                        if (v == lesson.correctAnswer) {
                          ref.read(learnerProfileProvider.notifier).addXp(20);
                        }
                      },
                    ),
                  ),
                  if (_answer != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_answer == lesson.correctAnswer ? TalkoraColors.iosGreen : TalkoraColors.iosOrange)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _answer == lesson.correctAnswer
                            ? (isAr ? 'إجابة صحيحة! (+20 XP)' : 'Correct! (+20 XP)')
                            : (isAr
                                ? 'حاول مرة أخرى — استمع جيداً للدرس.'
                                : 'Not quite — replay the audio and try again.'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _answer == lesson.correctAnswer ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
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

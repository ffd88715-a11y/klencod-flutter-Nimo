import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/ai_tool_executor.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/audio/voice_socket_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/permissions/mic_permission_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';
import 'package:talkora_ai/core/widgets/talkora_waveform.dart';

/// Nimo v5.0 Ultra — Key-Powered Live Human Voice Conversation Engine.
/// Uses the user's active API key & auto-discovered latest model for instant ultra-smart answers
/// AND routes speech to OpenAI HD / Groq Arabic PlayAI / ElevenLabs / Android Neural TTS.
class LiveVoiceScreen extends ConsumerStatefulWidget {
  const LiveVoiceScreen({super.key});

  @override
  ConsumerState<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends ConsumerState<LiveVoiceScreen> {
  final _micPermission = const MicPermissionService();
  final ScrollController _transcriptScrollCtrl = ScrollController();

  StreamSubscription<NativeVoiceEvent>? _voiceSub;
  Timer? _autoRestartTimer;

  VoiceEngineState _engineState = VoiceEngineState.listening;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isThinking = false;
  bool _isMuted = false;
  bool _sessionActive = false;
  bool _autoLoop = true;
  String _voiceLocale = 'ar-EG';
  double _speechRate = 1.0;
  String _activeVoiceEngineLabel = '';

  String _livePartialTranscript = '';
  String _statusNote = '';
  final List<AiChatMessage> _turns = [];

  final List<double> _amplitudes = List<double>.filled(28, 0.08, growable: true);
  double _currentLevel = 0.08;

  static const Map<String, String> _localeLabels = {
    'ar-EG': 'العربية (مصر)',
    'ar-SA': 'العربية (الفصحى)',
    'en-US': 'English (US)',
    'en-GB': 'English (UK)',
  };

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _autoLoop = ai.voiceAutoLoopEnabled;
    _voiceLocale = ai.voiceLocale;
    _speechRate = ai.voiceSpeechRate;
    _bindNativeVoiceStream();
  }

  void _bindNativeVoiceStream() {
    final bridge = ref.read(nativeBridgeProvider);
    _voiceSub = bridge.voiceEvents.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case 'ready':
          setState(() {
            _isListening = true;
            _engineState = VoiceEngineState.listening;
            _statusNote = '';
          });
          break;
        case 'rms':
          if (!_isMuted && _isListening) {
            setState(() => _pushAmplitude(event.level));
          }
          break;
        case 'partial':
          setState(() => _livePartialTranscript = event.text);
          break;
        case 'speech_end':
          setState(() => _engineState = VoiceEngineState.understanding);
          break;
        case 'final':
          final spoken = event.text.trim();
          setState(() {
            _isListening = false;
            _livePartialTranscript = '';
            _pushAmplitude(0.08);
          });
          if (spoken.isNotEmpty) {
            _processUserSpeech(spoken);
          } else if (_sessionActive && _autoLoop && !_isMuted) {
            _scheduleAutoListen(delayMs: 650);
          }
          break;
        case 'error':
          setState(() {
            _isListening = false;
            _pushAmplitude(0.08);
          });
          if ((event.code == 6 || event.code == 7) &&
              _sessionActive &&
              _autoLoop &&
              !_isMuted &&
              !_isThinking &&
              !_isSpeaking) {
            _scheduleAutoListen(delayMs: 700);
          } else if (event.code != 5) {
            setState(() {
              _engineState = VoiceEngineState.listening;
              _statusNote = event.message;
            });
          }
          break;
        case 'tts_start':
          setState(() {
            _isSpeaking = true;
            _engineState = VoiceEngineState.speaking;
          });
          break;
        case 'tts_done':
        case 'tts_stopped':
        case 'tts_error':
          setState(() {
            _isSpeaking = false;
            _pushAmplitude(0.08);
            if (!_isThinking && !_isListening) {
              _engineState = VoiceEngineState.listening;
            }
          });
          if (event.type == 'tts_done' && _sessionActive && _autoLoop && !_isMuted && !_isThinking) {
            _scheduleAutoListen(delayMs: 450);
          }
          break;
      }
    });
  }

  void _pushAmplitude(double normalized) {
    _currentLevel = normalized.clamp(0.06, 1.0);
    _amplitudes.removeAt(0);
    _amplitudes.add(_currentLevel);
  }

  void _scheduleAutoListen({int delayMs = 500}) {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted &&
          _sessionActive &&
          _autoLoop &&
          !_isMuted &&
          !_isThinking &&
          !_isSpeaking &&
          !_isListening) {
        _startListeningNow();
      }
    });
  }

  Future<void> _startListeningNow() async {
    final perm = await _micPermission.requestMicrophone();
    if (perm != MicPermissionResult.granted) {
      if (mounted) {
        final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'يرجى السماح بصلاحية الميكروفون لتشغيل المحادثة الصوتية.'
                  : 'Microphone permission is required for Live Voice.',
            ),
          ),
        );
      }
      return;
    }

    await ref.read(realisticTtsProvider).stop();

    setState(() {
      _sessionActive = true;
      _isMuted = false;
      _isSpeaking = false;
      _isListening = true;
      _livePartialTranscript = '';
      _statusNote = '';
      _engineState = VoiceEngineState.listening;
    });

    final ok = await ref.read(nativeBridgeProvider).startListening(locale: _voiceLocale);
    if (!ok && mounted) {
      setState(() {
        _isListening = false;
        _statusNote = 'تأكد من تفعيل خدمة Google Speech Services على الهاتف.';
      });
    }
  }

  Future<void> _toggleLiveMic() async {
    NimoSoundFx.click();
    final bridge = ref.read(nativeBridgeProvider);

    if (_isSpeaking) {
      await ref.read(realisticTtsProvider).stop();
      await _startListeningNow();
      return;
    }

    if (_isListening) {
      _autoRestartTimer?.cancel();
      await bridge.stopListening();
      setState(() {
        _isListening = false;
        _sessionActive = false;
        _pushAmplitude(0.08);
      });
      return;
    }

    await _startListeningNow();
  }

  Future<void> _interruptEverything() async {
    NimoSoundFx.click();
    _autoRestartTimer?.cancel();
    await ref.read(realisticTtsProvider).stop();
    await ref.read(nativeBridgeProvider).cancelListening();
    if (mounted) {
      setState(() {
        _isListening = false;
        _isSpeaking = false;
        _isThinking = false;
        _sessionActive = false;
        _engineState = VoiceEngineState.interrupted;
        _pushAmplitude(0.06);
      });
    }
  }

  Future<void> _processUserSpeech(String spokenText) async {
    final isAr = _voiceLocale.startsWith('ar') || NativeBridgeService.containsArabic(spokenText);
    final bridge = ref.read(nativeBridgeProvider);
    final executor = AiToolExecutor(bridge);

    setState(() {
      _turns.add(AiChatMessage(role: 'user', content: spokenText, timestamp: DateTime.now()));
      _isThinking = true;
      _statusNote = '';
      _engineState = VoiceEngineState.thinking;
    });
    _scrollToBottom();

    final aiSettings = ref.read(aiSettingsProvider);
    if (aiSettings.deviceControlEnabled) {
      final instant = await executor.tryInstantLocalCommand(spokenText, isArabic: isAr);
      if (instant != null && mounted) {
        setState(() {
          _isThinking = false;
          _turns.add(
            AiChatMessage(
              role: 'assistant',
              content: instant.cleanReply,
              timestamp: DateTime.now(),
              actionBadge: instant.actionBadge,
              imageUrl: instant.generatedImageUrl,
              modelUsed: 'Nimo Phone Engine',
            ),
          );
        });
        _scrollToBottom();
        await _speakHumanReply(instant.cleanReply);
        return;
      }
    }

    // Unified RAG from BOTH built-in 4,300+ DB and ALL injected GitHub/API datasets
    final unifiedRag = ref.read(nimoLocalDbProvider.notifier).buildOfflineRagContext(spokenText, limit: 5);
    final ghRag = ref.read(githubKnowledgeProvider.notifier).buildRagContext(spokenText);

    final voiceSystemPrompt = StringBuffer()
      ..writeln(
        isAr
            ? 'أنت Nimo v5.0 في وضع المحادثة الصوتية المباشرة. أجب بذكاء وقوة وبأسلوب بشري طبيعي ودود ومختصر (2 إلى 4 جمل واضحة بدون رموز ماركداون أو نجوم) لتكون مثالية للنطق الصوتي الواقعي. أجب بنفس لغة المستخدم.'
            : 'You are Nimo v5.0 in Realistic Live Voice mode. Speak like a sharp, warm human friend in 2-4 clear spoken sentences with zero markdown symbols.',
      );
    if (aiSettings.deviceControlEnabled) {
      voiceSystemPrompt.writeln(AiToolExecutor.systemToolPrompt);
    }

    final recentContext = _turns.length > 12 ? _turns.sublist(_turns.length - 12) : _turns;
    final aiService = ref.read(universalAiServiceProvider);
    final result = await aiService.sendChat(
      settings: aiSettings,
      messages: recentContext,
      systemPromptOverride: voiceSystemPrompt.toString(),
      ragContext: '$unifiedRag$ghRag',
    );

    if (!mounted) return;

    String replyText;
    String? actionBadge;
    String? imageUrl;
    String? modelBadge;

    if (result.success) {
      final outcome = aiSettings.deviceControlEnabled
          ? await executor.executeAiTags(result.text, isArabic: isAr)
          : ToolExecutionOutcome(cleanReply: result.text);
      replyText = outcome.cleanReply;
      actionBadge = outcome.actionBadge;
      imageUrl = outcome.generatedImageUrl;
      modelBadge = '${result.providerName} • ${result.modelName}';
      ref.read(learnerProfileProvider.notifier).incrementSpeakingMinutes(1);
    } else {
      final localHits = ref.read(nimoLocalDbProvider.notifier).search(spokenText, limit: 1);
      if (localHits.isNotEmpty) {
        replyText = '${localHits.first.title}. ${localHits.first.body}';
        modelBadge = 'Nimo Unified DB';
      } else {
        replyText = isAr
            ? 'تعذّر الاتصال بمفتاح ${aiSettings.activePreset.shortName}. يمكنك مراجعة المفتاح أو تبديل النموذج من الأعلى.'
            : 'Could not reach ${aiSettings.activePreset.shortName}. Check your API key or switch models above.';
        _statusNote = result.error ?? '';
      }
    }

    setState(() {
      _isThinking = false;
      _turns.add(
        AiChatMessage(
          role: 'assistant',
          content: replyText,
          timestamp: DateTime.now(),
          modelUsed: modelBadge,
          actionBadge: actionBadge,
          imageUrl: imageUrl,
        ),
      );
    });
    _scrollToBottom();
    await _speakHumanReply(replyText);
  }

  Future<void> _speakHumanReply(String text) async {
    final aiSettings = ref.read(aiSettingsProvider);
    final ttsLocale = NativeBridgeService.containsArabic(text)
        ? (_voiceLocale.startsWith('ar') ? _voiceLocale : 'ar-EG')
        : (_voiceLocale.startsWith('en') ? _voiceLocale : 'en-US');

    final engineUsed = await ref.read(realisticTtsProvider).speakHuman(
          text: text,
          aiSettings: aiSettings,
          locale: ttsLocale,
          rate: _speechRate,
          onStart: () {
            if (!mounted) return;
            setState(() {
              _isSpeaking = true;
              _engineState = VoiceEngineState.speaking;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _isSpeaking = false;
              _pushAmplitude(0.08);
              if (!_isThinking && !_isListening) {
                _engineState = VoiceEngineState.listening;
              }
            });
            if (_sessionActive && _autoLoop && !_isMuted && !_isThinking) {
              _scheduleAutoListen(delayMs: 420);
            }
          },
        );
    if (mounted) {
      setState(() => _activeVoiceEngineLabel = engineUsed);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScrollCtrl.hasClients) {
        _transcriptScrollCtrl.animateTo(
          _transcriptScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showKeyProviderSwitcher() {
    NimoSoundFx.click();
    final ai = ref.read(aiSettingsProvider);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAr ? 'اختر مفتاح الذكاء للصوت اللايف' : 'Choose API Key for Voice AI',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/settings');
                  },
                  child: Text(isAr ? 'إضافة مفتاح' : 'Add Key'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...AiProviderCatalog.all.map((p) {
              final hasKey = !p.requiresApiKey || (ai.credentials[p.id]?.apiKey.trim().isNotEmpty ?? false);
              final active = ai.activeProviderId == p.id;
              return ListTile(
                leading: IosIconBadge(icon: p.icon, color: p.badgeColor),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ai.credentialFor(p.id).model),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasKey)
                      const Icon(CupertinoIcons.checkmark_circle_fill, color: TalkoraColors.iosGreen, size: 18),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Icon(CupertinoIcons.check_mark, color: Theme.of(context).colorScheme.primary),
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
      ),
    );
  }

  void _openQuickTypeDialog() {
    NimoSoundFx.click();
    final ctrl = TextEditingController();
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'اكتب لمساعد Nimo الصوتي' : 'Type to Nimo Voice'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isAr ? 'اسأل أي سؤال أو أعطِ أمراً صوتياً...' : 'Ask anything or give a command...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () {
              NimoSoundFx.pop();
              final txt = ctrl.text.trim();
              Navigator.pop(ctx);
              if (txt.isNotEmpty) _processUserSpeech(txt);
            },
            child: Text(isAr ? 'إرسال' : 'Send'),
          ),
        ],
      ),
    );
  }

  void _showVoiceProfilePicker() {
    NimoSoundFx.click();
    final ai = ref.read(aiSettingsProvider);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
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
              isAr ? 'اختر محرك الصوت البشري' : 'Choose Realistic Human Voice',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? 'يعمل تلقائياً بالمفتاح الموضوع (OpenAI HD أو Groq PlayAI العربي أو ElevenLabs) مع بديل محلي فوري.'
                  : 'Automatically uses your configured API key (OpenAI HD, Groq PlayAI, ElevenLabs) with offline Neural fallback.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ...RealisticTtsService.presets.map((p) {
              final sel = ai.voicePresetId == p.id;
              return ListTile(
                leading: IosIconBadge(
                  icon: CupertinoIcons.waveform_circle_fill,
                  color: sel ? TalkoraColors.iosGreen : TalkoraColors.iosBlue,
                ),
                title: Text(isAr ? p.labelAr : p.labelEn, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: sel ? const Icon(CupertinoIcons.checkmark_alt, color: TalkoraColors.iosGreen) : null,
                onTap: () {
                  NimoSoundFx.click();
                  ref.read(aiSettingsProvider.notifier).updateAdvanced(voicePresetId: p.id);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  String _stateHeadline(bool isAr) {
    if (_isListening) return isAr ? 'أستمع إليك الآن... تحدث بحرية' : 'Listening... Speak naturally';
    if (_isThinking) return isAr ? 'Nimo يفكر باستخدام مفتاحك النشط...' : 'Thinking with your active API key...';
    if (_isSpeaking) return isAr ? 'Nimo يتحدث الآن (اضغط للمقاطعة)' : 'Nimo Speaking (Tap to interrupt)';
    return isAr ? 'اضغط على الميكروفون للتحدث مع Nimo' : 'Tap microphone to talk with Nimo';
  }

  @override
  void dispose() {
    _autoRestartTimer?.cancel();
    _voiceSub?.cancel();
    _transcriptScrollCtrl.dispose();
    ref.read(nativeBridgeProvider).cancelListening();
    ref.read(realisticTtsProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);
    final localDb = ref.watch(nimoLocalDbProvider);
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ttsEngine = _activeVoiceEngineLabel.isNotEmpty
        ? _activeVoiceEngineLabel
        : RealisticTtsService.describeActiveVoiceEngine(ai, isAr: isAr);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () {
            NimoSoundFx.click();
            context.pop();
          },
        ),
        title: GestureDetector(
          onTap: _showKeyProviderSwitcher,
          child: Column(
            children: [
              Text(isAr ? 'التحدث الصوتي الذكي' : 'Nimo Live Voice', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              IosStatusPill(
                label: '${ai.activePreset.shortName} • ${ai.activeModel}',
                color: _isListening
                    ? TalkoraColors.iosGreen
                    : (_isSpeaking ? TalkoraColors.iosBlue : TalkoraColors.iosIndigo),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: isAr ? 'اختيار الصوت' : 'Voice Profile',
            icon: const Icon(CupertinoIcons.waveform_circle, size: 22),
            onPressed: _showVoiceProfilePicker,
          ),
          IconButton(
            tooltip: isAr ? 'إرسال نص' : 'Quick Type',
            icon: const Icon(CupertinoIcons.keyboard, size: 21),
            onPressed: _openQuickTypeDialog,
          ),
          if (_turns.isNotEmpty)
            IconButton(
              tooltip: isAr ? 'مسح المحادثة' : 'Clear',
              icon: const Icon(CupertinoIcons.trash, size: 19),
              onPressed: () => setState(() => _turns.clear()),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ActionChip(
                        avatar: const Icon(CupertinoIcons.lock_shield_fill, size: 15, color: TalkoraColors.iosGreen),
                        label: Text(ttsEngine, style: const TextStyle(fontSize: 11.5)),
                        onPressed: _showVoiceProfilePicker,
                      ),
                    ),
                    ..._localeLabels.entries.map((entry) {
                      final selected = _voiceLocale == entry.key;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          onSelected: (_) {
                            NimoSoundFx.click();
                            setState(() => _voiceLocale = entry.key);
                            ref.read(aiSettingsProvider.notifier).updateAdvanced(voiceLocale: entry.key);
                          },
                        ),
                      );
                    }),
                    FilterChip(
                      avatar: Icon(CupertinoIcons.repeat, size: 15, color: _autoLoop ? theme.colorScheme.primary : null),
                      label: Text(isAr ? 'استماع مستمر' : 'Hands-Free', style: const TextStyle(fontSize: 12)),
                      selected: _autoLoop,
                      onSelected: (v) {
                        NimoSoundFx.click();
                        setState(() => _autoLoop = v);
                        ref.read(aiSettingsProvider.notifier).updateAdvanced(voiceAutoLoopEnabled: v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              GestureDetector(
                onTap: _toggleLiveMic,
                child: TalkoraVoiceOrb(
                  state: _engineState,
                  audioLevel: _isSpeaking ? 0.45 : _currentLevel,
                  size: 136,
                ),
              ),
              const SizedBox(height: 10),
              Text(_stateHeadline(isAr), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (localDb.totalRecords > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    isAr
                        ? 'مرتبط بمفتاح ${ai.activePreset.shortName} + ${localDb.totalRecords} سجل معرفي'
                        : 'Powered by ${ai.activePreset.shortName} + ${localDb.totalRecords} records',
                    style: theme.textTheme.bodySmall?.copyWith(color: TalkoraColors.iosGreen),
                  ),
                ),
              if (_statusNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _statusNote,
                    style: theme.textTheme.bodySmall?.copyWith(color: TalkoraColors.iosOrange),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),

              TalkoraWaveform(
                amplitudeHistory: _amplitudes,
                height: 40,
                color: _isSpeaking ? TalkoraColors.iosGreen : theme.colorScheme.primary,
              ),

              if (_livePartialTranscript.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _livePartialTranscript,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 8),

              Expanded(
                child: _turns.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            isAr
                                ? 'تحدث مباشرة الآن! يعمل الصوت بأحدث موديل على مفتاحك مع قواعد البيانات المحقونة.'
                                : 'Speak freely! Powered by your active API key and injected knowledge base.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _transcriptScrollCtrl,
                        itemCount: _turns.length,
                        itemBuilder: (context, idx) {
                          final msg = _turns[idx];
                          final isUser = msg.role == 'user';
                          return Align(
                            alignment: isUser
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? theme.colorScheme.primary
                                    : (isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (msg.actionBadge != null) ...[
                                    IosStatusPill(
                                      label: msg.actionBadge!,
                                      color: TalkoraColors.iosGreen,
                                      icon: CupertinoIcons.checkmark_seal_fill,
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  SelectableText(
                                    msg.content,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: isUser ? Colors.white : null,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (!isUser) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (msg.modelUsed != null)
                                          Flexible(
                                            child: Text(
                                              msg.modelUsed!,
                                              style: theme.textTheme.bodySmall,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => _speakHumanReply(msg.content),
                                          child: const Icon(CupertinoIcons.speaker_2_fill,
                                              size: 16, color: TalkoraColors.iosTeal),
                                        ),
                                        const SizedBox(width: 10),
                                        NimoCopyChip(textToCopy: msg.content, isAr: isAr, compact: true),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(CupertinoIcons.speedometer, size: 17, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(isAr ? 'السرعة' : 'Speed', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: CupertinoSlider(
                      value: _speechRate.clamp(0.65, 1.5),
                      min: 0.65,
                      max: 1.5,
                      divisions: 10,
                      activeColor: theme.colorScheme.primary,
                      onChanged: (v) {
                        setState(() => _speechRate = v);
                        ref.read(aiSettingsProvider.notifier).updateAdvanced(voiceSpeechRate: v);
                      },
                    ),
                  ),
                  Text('${_speechRate.toStringAsFixed(1)}x', style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    onPressed: () {
                      NimoSoundFx.click();
                      setState(() => _isMuted = !_isMuted);
                      if (_isMuted) ref.read(nativeBridgeProvider).cancelListening();
                    },
                    icon: Icon(_isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill),
                  ),
                  IconButton.filledTonal(
                    onPressed: _interruptEverything,
                    icon: const Icon(CupertinoIcons.stop_fill),
                  ),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        backgroundColor: _isListening
                            ? TalkoraColors.iosRed
                            : (_isSpeaking ? TalkoraColors.iosOrange : theme.colorScheme.primary),
                      ),
                      onPressed: _toggleLiveMic,
                      child: Icon(
                        _isListening
                            ? CupertinoIcons.stop_circle
                            : (_isSpeaking ? CupertinoIcons.hand_raised_fill : CupertinoIcons.mic_fill),
                        size: 30,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: TalkoraColors.iosRed.withValues(alpha: 0.14),
                      foregroundColor: TalkoraColors.iosRed,
                    ),
                    onPressed: () {
                      _interruptEverything();
                      context.pop();
                    },
                    icon: const Icon(CupertinoIcons.phone_down_fill),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

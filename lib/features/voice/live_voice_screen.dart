import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/ai_tool_executor.dart';
import 'package:talkora_ai/core/audio/nabra_voice_engine.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/permissions/mic_permission_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

class _NabraTurn {
  final String role; // 'user' | 'assistant'
  final String text;
  final String emotionLabel;
  final String? actionBadge;
  final String? voiceDirection;
  final bool isSinging;
  final String imitationStyle;
  final List<NabraSourceLink> sources;
  final DateTime timestamp;

  const _NabraTurn({
    required this.role,
    required this.text,
    this.emotionLabel = '',
    this.actionBadge,
    this.voiceDirection,
    this.isSinging = false,
    this.imitationStyle = '',
    this.sources = const [],
    required this.timestamp,
  });
}

/// Nimo v9.5 Nabra Studio — Realistic Egyptian Live Voice Call Screen.
/// Integrates the full Nabra Live voice architecture (Gemini 2.5 Flash Preview TTS,
/// Youssef/Salma human voices, Studio Warmth EQ/Compressor DSP, Singing & Vocal Imitation,
/// Live Google Search Grounding, Live Orb Visualizer & Full Phone Control).
class LiveVoiceScreen extends ConsumerStatefulWidget {
  const LiveVoiceScreen({super.key});

  @override
  ConsumerState<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends ConsumerState<LiveVoiceScreen> with SingleTickerProviderStateMixin {
  final _micPermission = const MicPermissionService();
  final ScrollController _transcriptScrollCtrl = ScrollController();
  final TextEditingController _quickTextCtrl = TextEditingController();
  final TextEditingController _customImitationCtrl = TextEditingController();

  late final AnimationController _orbAnimCtrl;
  StreamSubscription<NativeVoiceEvent>? _voiceSub;
  Timer? _autoRestartTimer;
  Timer? _callTimer;

  // Nabra Live studio state
  String _selectedVoiceId = 'Puck'; // 'Puck' (يوسف) | 'Leda' (سلمى)
  String _selectedPersonaId = 'wise';
  String _selectedSpicinessId = 'chill';
  String _selectedImitationId = 'calm_natural';
  String _customImitation = '';
  bool _singingMode = false;
  bool _liveSearchEnabled = true;

  // Live call state
  bool _isConnected = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isThinking = false;
  bool _isMuted = false;
  bool _autoLoop = true;
  int _callSeconds = 0;
  double _audioLevel = 0.08;
  String _livePartialTranscript = '';
  String _liveMoodLabel = '';
  String _activeEngineLabel = '';
  String _statusNote = '';

  final List<_NabraTurn> _turns = [];

  NabraSessionConfig get _nabraConfig => NabraSessionConfig(
        selectedVoiceId: _selectedVoiceId,
        selectedPersonaId: _selectedPersonaId,
        selectedSpicinessId: _selectedSpicinessId,
        selectedImitationId: _selectedImitationId,
        customImitation: _customImitation,
        singingMode: _singingMode,
        liveSearchEnabled: _liveSearchEnabled,
      );

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _autoLoop = ai.voiceAutoLoopEnabled;
    if (ai.voicePresetId == 'nabra_salma') {
      _selectedVoiceId = 'Leda';
    }
    _orbAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _bindNativeVoiceStream();
  }

  @override
  void dispose() {
    _autoRestartTimer?.cancel();
    _callTimer?.cancel();
    _voiceSub?.cancel();
    _orbAnimCtrl.dispose();
    _transcriptScrollCtrl.dispose();
    _quickTextCtrl.dispose();
    _customImitationCtrl.dispose();
    ref.read(realisticTtsProvider).stop();
    ref.read(nativeBridgeProvider).cancelListening();
    super.dispose();
  }

  void _bindNativeVoiceStream() {
    final bridge = ref.read(nativeBridgeProvider);
    _voiceSub = bridge.voiceEvents.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case 'ready':
          setState(() {
            _isListening = true;
            _statusNote = '';
          });
          break;
        case 'rms':
          if (!_isMuted && _isListening) {
            setState(() => _audioLevel = event.level.clamp(0.06, 1.0));
          }
          break;
        case 'partial':
          setState(() => _livePartialTranscript = event.text);
          break;
        case 'final':
          final spoken = event.text.trim();
          setState(() {
            _isListening = false;
            _livePartialTranscript = '';
            _audioLevel = 0.08;
          });
          if (spoken.isNotEmpty) {
            _processConversationTurn(spoken);
          } else if (_isConnected && _autoLoop && !_isMuted && !_isThinking && !_isSpeaking) {
            _scheduleAutoListen(delayMs: 650);
          }
          break;
        case 'error':
          setState(() {
            _isListening = false;
            _audioLevel = 0.08;
          });
          if ((event.code == 6 || event.code == 7) &&
              _isConnected &&
              _autoLoop &&
              !_isMuted &&
              !_isThinking &&
              !_isSpeaking) {
            _scheduleAutoListen(delayMs: 700);
          } else if (event.code != 5 && event.message.isNotEmpty) {
            setState(() => _statusNote = event.message);
          }
          break;
        case 'tts_start':
          setState(() => _isSpeaking = true);
          break;
        case 'tts_done':
        case 'tts_stopped':
        case 'tts_error':
          setState(() {
            _isSpeaking = false;
            _audioLevel = 0.08;
          });
          if (event.type == 'tts_done' && _isConnected && _autoLoop && !_isMuted && !_isThinking) {
            _scheduleAutoListen(delayMs: 450);
          }
          break;
      }
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isConnected) {
        setState(() => _callSeconds += 1);
      }
    });
  }

  String get _formattedTimer {
    final m = (_callSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _scheduleAutoListen({int delayMs = 500}) {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted && _isConnected && _autoLoop && !_isMuted && !_isThinking && !_isSpeaking && !_isListening) {
        _startMicListening();
      }
    });
  }

  Future<bool> _startMicListening() async {
    final perm = await _micPermission.requestMicrophone();
    if (perm != MicPermissionResult.granted) {
      if (mounted) {
        setState(() => _isMuted = true);
      }
      return false;
    }
    await ref.read(realisticTtsProvider).stop();
    if (mounted) {
      setState(() {
        _isListening = true;
        _isSpeaking = false;
        _livePartialTranscript = '';
        _statusNote = '';
      });
    }
    final ok = await ref.read(nativeBridgeProvider).startListening(locale: 'ar-EG');
    if (!ok && mounted) {
      setState(() {
        _isListening = false;
        _statusNote = 'يمكنك التحدث عبر الكتابة السريعة بالأسفل وسماع الصوت الواقعي.';
      });
    }
    return ok;
  }

  Future<void> _startLiveCall({bool skipGreeting = false}) async {
    if (_isConnected) return;
    NimoSoundFx.pop();
    setState(() {
      _isConnected = true;
      _isMuted = false;
      _statusNote = '';
    });
    _startCallTimer();

    final voice = NabraVoiceEngine.voiceById(_selectedVoiceId);
    final persona = NabraVoiceEngine.personaById(_selectedPersonaId);

    if (!skipGreeting && _turns.isEmpty) {
      final greetingLine = voice.greeting;
      setState(() {
        _liveMoodLabel = 'هادئ ومستعد ${persona.emoji}';
        _turns.add(
          _NabraTurn(
            role: 'assistant',
            text: greetingLine,
            emotionLabel: _liveMoodLabel,
            voiceDirection: 'very calm, warm, gentle breath then welcoming eloquent Cairene greeting',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      await _speakNabraReply(
        greetingLine,
        voiceDirection: 'very calm, warm, gentle breath then welcoming eloquent Cairene greeting',
      );
    } else {
      await _startMicListening();
    }
  }

  Future<void> _endLiveCall() async {
    NimoSoundFx.click();
    _autoRestartTimer?.cancel();
    _callTimer?.cancel();
    await ref.read(realisticTtsProvider).stop();
    await ref.read(nativeBridgeProvider).cancelListening();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isListening = false;
        _isSpeaking = false;
        _isThinking = false;
        _isMuted = false;
        _audioLevel = 0.08;
      });
    }
  }

  Future<void> _stopSpeakingNow() async {
    NimoSoundFx.click();
    await ref.read(realisticTtsProvider).stop();
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _audioLevel = 0.08;
      });
      if (_isConnected && !_isMuted) {
        _scheduleAutoListen(delayMs: 300);
      }
    }
  }

  Future<void> _toggleMute() async {
    if (!_isConnected) return;
    NimoSoundFx.click();
    if (_isMuted) {
      setState(() => _isMuted = false);
      await _startMicListening();
    } else {
      _autoRestartTimer?.cancel();
      await ref.read(nativeBridgeProvider).cancelListening();
      setState(() {
        _isMuted = true;
        _isListening = false;
      });
    }
  }

  Future<void> _processConversationTurn(String userText) async {
    final cleanInput = userText.trim();
    if (cleanInput.isEmpty || _isThinking) return;

    if (!_isConnected) {
      await _startLiveCall(skipGreeting: true);
    }

    await ref.read(realisticTtsProvider).stop();
    await ref.read(nativeBridgeProvider).cancelListening();

    setState(() {
      _turns.add(_NabraTurn(role: 'user', text: cleanInput, timestamp: DateTime.now()));
      _isThinking = true;
      _isListening = false;
      _statusNote = '';
    });
    _scrollToBottom();

    final aiSettings = ref.read(aiSettingsProvider);
    final bridge = ref.read(nativeBridgeProvider);
    final executor = AiToolExecutor(bridge);
    final isAr = NativeBridgeService.containsArabic(cleanInput) ||
        ref.read(learnerProfileProvider).uiLocale == 'ar';

    // 1. Instant local phone command (SMS reading, Contacts, Calls, Apps, Flashlight, Floating Bubble)
    if (aiSettings.deviceControlEnabled) {
      final instant = await executor.tryInstantLocalCommand(cleanInput, isArabic: isAr);
      if (instant != null && mounted) {
        setState(() {
          _isThinking = false;
          _liveMoodLabel = 'تحكم فوري بالهاتف ⚡';
          _turns.add(
            _NabraTurn(
              role: 'assistant',
              text: instant.cleanReply,
              emotionLabel: _liveMoodLabel,
              actionBadge: instant.actionBadge,
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
        await _speakNabraReply(instant.cleanReply);
        return;
      }
    }

    // 2. Build RAG context
    final unifiedRag = ref.read(nimoLocalDbProvider.notifier).buildOfflineRagContext(cleanInput, limit: 4);
    final ghRag = ref.read(githubKnowledgeProvider.notifier).buildRagContext(cleanInput);
    final combinedRag = '$unifiedRag$ghRag';

    final historyMessages = _turns
        .map((t) => AiChatMessage(role: t.role, content: t.text, timestamp: t.timestamp))
        .toList();

    final geminiKey = aiSettings.credentialFor('gemini').apiKey.trim();

    String replyText = '';
    String emotionLabel = 'هادئ وذكي ✨';
    String voiceDirection = '';
    bool isSinging = _singingMode;
    String imitationStyle = _customImitation.trim();
    String? actionBadge;
    List<NabraSourceLink> sources = const [];

    // 3A. Primary Nabra Live Engine via Gemini (supports JSON emotion/singing/imitation + Google Search Grounding!)
    if (geminiKey.isNotEmpty) {
      final nabraRes = await ref.read(nabraVoiceEngineProvider).generateNabraReply(
            geminiApiKey: geminiKey,
            config: _nabraConfig,
            history: historyMessages,
            userText: cleanInput,
            ragContext: combinedRag,
            extraToolPrompt: aiSettings.deviceControlEnabled ? AiToolExecutor.systemToolPrompt : '',
          );
      if (nabraRes.success && nabraRes.reply.trim().isNotEmpty) {
        final outcome = aiSettings.deviceControlEnabled
            ? await executor.executeAiTags(nabraRes.reply, isArabic: isAr)
            : ToolExecutionOutcome(cleanReply: nabraRes.reply);
        replyText = outcome.cleanReply;
        actionBadge = outcome.actionBadge;
        emotionLabel = nabraRes.emotionLabel;
        voiceDirection = nabraRes.voiceDirection;
        isSinging = nabraRes.isSinging || _singingMode;
        imitationStyle = nabraRes.imitationStyle.isNotEmpty ? nabraRes.imitationStyle : _customImitation.trim();
        sources = nabraRes.sources;
      }
    }

    // 3B. Seamless fallback to UniversalAiService (OpenAI / Groq / DeepSeek / Claude / Free Cloud)
    if (replyText.isEmpty) {
      final sysPrompt = NabraVoiceEngine.buildSystemInstruction(
        _nabraConfig,
        extraToolPrompt: aiSettings.deviceControlEnabled ? AiToolExecutor.systemToolPrompt : '',
      );
      final aiRes = await ref.read(universalAiServiceProvider).sendChat(
            settings: aiSettings,
            messages: historyMessages,
            systemPromptOverride: '$sysPrompt\nتحدث مباشرة بالعربية المصرية الهادئة بدون أي رموز ماركداون.',
            ragContext: combinedRag,
          );
      if (aiRes.success && aiRes.text.trim().isNotEmpty) {
        var cleaned = aiRes.text.trim();
        if (cleaned.startsWith('{') || cleaned.contains('"reply"')) {
          try {
            final match = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(cleaned);
            if (match != null) {
              cleaned = match.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
            }
          } catch (_) {}
        }
        final outcome = aiSettings.deviceControlEnabled
            ? await executor.executeAiTags(cleaned, isArabic: isAr)
            : ToolExecutionOutcome(cleanReply: cleaned);
        replyText = outcome.cleanReply;
        actionBadge = outcome.actionBadge;
        emotionLabel = 'نَبْرة ذكي • ${aiRes.providerName}';
      } else {
        replyText = 'حصلت مشكلة بسيطة في الاتصال، جرّب تاني أو راجع مفتاح Gemini من الإعدادات.';
        _statusNote = aiRes.error ?? '';
      }
    }

    if (!mounted) return;
    ref.read(learnerProfileProvider.notifier).incrementSpeakingMinutes(1);
    setState(() {
      _isThinking = false;
      _liveMoodLabel = emotionLabel;
      _turns.add(
        _NabraTurn(
          role: 'assistant',
          text: replyText,
          emotionLabel: emotionLabel,
          actionBadge: actionBadge,
          voiceDirection: voiceDirection,
          isSinging: isSinging,
          imitationStyle: imitationStyle,
          sources: sources,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    await _speakNabraReply(
      replyText,
      voiceDirection: voiceDirection,
      isSinging: isSinging,
      imitationStyle: imitationStyle,
    );
  }

  Future<void> _speakNabraReply(
    String text, {
    String voiceDirection = '',
    bool? isSinging,
    String? imitationStyle,
  }) async {
    final aiSettings = ref.read(aiSettingsProvider);
    final engineUsed = await ref.read(realisticTtsProvider).speakHuman(
          text: text,
          aiSettings: aiSettings,
          nabraConfig: _nabraConfig,
          voiceDirection: voiceDirection,
          isSinging: isSinging,
          imitationStyle: imitationStyle,
          onStart: () {
            if (mounted) {
              setState(() {
                _isSpeaking = true;
                _audioLevel = 0.65;
              });
            }
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _isSpeaking = false;
              _audioLevel = 0.08;
            });
            if (_isConnected && _autoLoop && !_isMuted && !_isThinking) {
              _scheduleAutoListen(delayMs: 420);
            }
          },
        );
    if (mounted) {
      setState(() => _activeEngineLabel = engineUsed);
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

  void _openStudioSettingsSheet() {
    NimoSoundFx.click();
    _customImitationCtrl.text = _customImitation;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0D111A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            children: [
              const Text(
                'استوديو نَبْرة لايف — الشخصية والتقليد والغناء',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 14),

              // 1. Live Search + Singing Mode toggles
              Row(
                children: [
                  Expanded(
                    child: _TogglePillButton(
                      active: _liveSearchEnabled,
                      activeColor: const Color(0xFF10B981),
                      label: _liveSearchEnabled ? '🌐 معلومات حية: مفعّل' : '🌐 معلومات حية: مغلق',
                      onTap: () {
                        NimoSoundFx.click();
                        setState(() => _liveSearchEnabled = !_liveSearchEnabled);
                        setSheet(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TogglePillButton(
                      active: _singingMode,
                      activeColor: const Color(0xFFF59E0B),
                      label: _singingMode ? '🎵 وضع الغناء: شغّال' : '🎵 وضع الغناء: مغلق',
                      onTap: () {
                        NimoSoundFx.click();
                        setState(() => _singingMode = !_singingMode);
                        setSheet(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Personas
              const Text('شخصية اللي بتكلمه', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: NabraVoiceEngine.personas.map((p) {
                  final sel = p.id == _selectedPersonaId;
                  return ChoiceChip(
                    selected: sel,
                    label: Text('${p.emoji} ${p.name}'),
                    onSelected: (_) {
                      NimoSoundFx.click();
                      setState(() => _selectedPersonaId = p.id);
                      setSheet(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 3. Spiciness / Calmness
              const Text('مستوى الصراحة والهدوء', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: NabraVoiceEngine.spicinessLevels.map((sp) {
                  final sel = sp.id == _selectedSpicinessId;
                  return ChoiceChip(
                    selected: sel,
                    label: Text(sp.name),
                    onSelected: (_) {
                      NimoSoundFx.click();
                      setState(() => _selectedSpicinessId = sp.id);
                      setSheet(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 4. Imitation & Singing Modes
              const Text('أنماط التقليد والأداء الصوتي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: NabraVoiceEngine.imitationModes.map((m) {
                  final sel = _customImitation.trim().isEmpty && m.id == _selectedImitationId;
                  return ChoiceChip(
                    selected: sel,
                    label: Text('${m.emoji} ${m.name}'),
                    onSelected: (_) {
                      NimoSoundFx.click();
                      setState(() {
                        _selectedImitationId = m.id;
                        _customImitation = '';
                        _customImitationCtrl.clear();
                        _singingMode = m.isSinging;
                      });
                      setSheet(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // 5. Custom Imitation Field
              TextField(
                controller: _customImitationCtrl,
                onChanged: (v) {
                  setState(() => _customImitation = v);
                  setSheet(() {});
                },
                decoration: InputDecoration(
                  labelText: 'أو اكتب أي صوت/شخصية يقلدها أو يغني بيها',
                  hintText: 'مثال: مطرب طربي قديم، معلق ماتش، راوي وثائقي...',
                  suffixIcon: IconButton(
                    icon: const Icon(CupertinoIcons.clear_circled_solid, size: 18),
                    onPressed: () {
                      _customImitationCtrl.clear();
                      setState(() {
                        _customImitation = '';
                        _selectedImitationId = 'calm_natural';
                        _singingMode = false;
                      });
                      setSheet(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('استماع تلقائي مستمر بعد كل رد', style: TextStyle(fontSize: 13.5)),
                value: _autoLoop,
                onChanged: (v) {
                  setState(() => _autoLoop = v);
                  ref.read(aiSettingsProvider.notifier).updateAdvanced(voiceAutoLoopEnabled: v);
                  setSheet(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);
    final hasGeminiKey = ai.credentialFor('gemini').apiKey.trim().isNotEmpty;
    final activeVoice = NabraVoiceEngine.voiceById(_selectedVoiceId);
    final activePersona = NabraVoiceEngine.personaById(_selectedPersonaId);
    final activeImitation = NabraVoiceEngine.imitationById(_selectedImitationId);

    final String orbCenterLabel;
    final String statusSub;
    final Color orbColor;

    if (!_isConnected) {
      orbCenterLabel = 'أوفلاين';
      statusSub = 'اضغط ابدأ المكالمة أو اختر جملة سريعة';
      orbColor = const Color(0xFF64748B);
    } else if (_isThinking) {
      orbCenterLabel = 'بيفكر';
      statusSub = '${activeVoice.name} بيفكرلك في رد...';
      orbColor = const Color(0xFF2DD4BF);
    } else if (_isSpeaking) {
      orbCenterLabel = 'بيتكلم';
      statusSub = '${activeVoice.name} بيتكلم دلوقتي 🔊';
      orbColor = const Color(0xFFF59E0B);
    } else if (_isListening) {
      orbCenterLabel = 'سامعك';
      statusSub = _livePartialTranscript.isNotEmpty ? _livePartialTranscript : 'اتكلم دلوقتي، أنا سامعك 🎙️';
      orbColor = const Color(0xFF10B981);
    } else if (_isMuted) {
      orbCenterLabel = 'مكتوم';
      statusSub = 'المايك مكتوم — اكتب رسالة أو افتح المايك';
      orbColor = const Color(0xFFF59E0B);
    } else {
      orbCenterLabel = 'مباشر';
      statusSub = 'اضغط المايك أو اكتب رسالة';
      orbColor = const Color(0xFF10B981);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D111A),
        title: Row(
          children: [
            const Text('نَبْرة لايف', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 8),
            if (_isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2234),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                ),
                child: Text(
                  _formattedTimer,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'استوديو الشخصية والتقليد والغناء',
            icon: const Icon(CupertinoIcons.slider_horizontal_3, color: Color(0xFF34D399)),
            onPressed: _openStudioSettingsSheet,
          ),
          IconButton(
            tooltip: 'إعدادات مفاتيح AI',
            icon: const Icon(CupertinoIcons.lock_shield_fill, color: Color(0xFFF59E0B)),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top compact voice selector (يوسف / سلمى) + active mode badge
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: const Color(0xFF0D111A),
            child: Column(
              children: [
                Row(
                  children: NabraVoiceEngine.voices.map((v) {
                    final active = v.id == _selectedVoiceId;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: v.id == 'Puck' ? 6 : 0, right: v.id == 'Leda' ? 6 : 0),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            NimoSoundFx.click();
                            ref.read(realisticTtsProvider).stop();
                            setState(() => _selectedVoiceId = v.id);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFF1A2234) : const Color(0xFF121621),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: active ? const Color(0xFFF59E0B).withValues(alpha: 0.8) : Colors.white12,
                                width: active ? 1.2 : 0.7,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(v.emoji, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        v.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: active ? const Color(0xFFFCD34D) : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        v.ageLabel,
                                        style: const TextStyle(fontSize: 10.5, color: Colors.white60),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${activePersona.emoji} ${activePersona.name} • ${_customImitation.trim().isNotEmpty ? 'تقليد: ${_customImitation.trim()}' : '${activeImitation.emoji} ${activeImitation.name}'}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF6EE7B7), fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_liveMoodLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _liveMoodLabel,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFFFDE68A), fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                if (!hasGeminiKey)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: () => context.push('/settings'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                        ),
                        child: const Text(
                          'أضف مفتاح Gemini API في الإعدادات لتفعيل صوت نَبْرة البشري الواقعي 100% (Gemini 2.5 TTS)',
                          style: TextStyle(fontSize: 11, color: Color(0xFFFCD34D), fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Live Orb Stage + Call Controls
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0E17),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!_isConnected) {
                      _startLiveCall();
                    } else if (_isSpeaking) {
                      _stopSpeakingNow();
                    } else {
                      _startMicListening();
                    }
                  },
                  child: SizedBox(
                    width: 154,
                    height: 154,
                    child: AnimatedBuilder(
                      animation: _orbAnimCtrl,
                      builder: (_, __) {
                        final phase = _orbAnimCtrl.value * 2 * math.pi * 3;
                        final level = _isSpeaking
                            ? (0.45 + 0.35 * math.sin(phase * 1.6).abs())
                            : (_isListening ? _audioLevel : (_isThinking ? 0.25 : 0.05));
                        return CustomPaint(
                          painter: _NabraLiveOrbPainter(
                            phase: phase,
                            level: level,
                            color: orbColor,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  orbCenterLabel,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_activeEngineLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _activeEngineLabel,
                                      style: const TextStyle(fontSize: 9.5, color: Colors.white60),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusNote.isNotEmpty ? _statusNote : statusSub,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mute toggle
                    IconButton.filledTonal(
                      onPressed: _isConnected ? _toggleMute : null,
                      icon: Icon(
                        _isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill,
                        color: _isMuted ? TalkoraColors.iosRed : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Start / End Call Button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _isConnected ? const Color(0xFFE11D48) : const Color(0xFF10B981),
                        foregroundColor: _isConnected ? Colors.white : const Color(0xFF07090F),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      ),
                      onPressed: _isConnected ? _endLiveCall : () => _startLiveCall(),
                      icon: Icon(_isConnected ? CupertinoIcons.phone_down_fill : CupertinoIcons.phone_fill, size: 18),
                      label: Text(
                        _isConnected ? 'إنهاء المكالمة' : 'ابدأ المكالمة الآن',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Stop / Interrupt Speaking
                    IconButton.filledTonal(
                      onPressed: _isSpeaking ? _stopSpeakingNow : null,
                      icon: const Icon(CupertinoIcons.stop_fill, color: Color(0xFFF59E0B)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 4 Quick Egyptian Demo Chips (same as Nabra Live!)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _QuickChip(
                        label: '🎵 غنيلي بطرب',
                        onTap: () => _processConversationTurn(
                          'غنيلي مقطع أغنية مصرية هادية وطربية عن القمر والليل بإحساس عالي أوي.',
                        ),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '⚽ قلد معلق كورة',
                        onTap: () => _processConversationTurn(
                          'قلدلي صوت معلق كرة قدم مصري متحمس بيعلق على جون عالمي في الدقيقة 90!',
                        ),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '🧠 معلومة عميقة',
                        onTap: () => _processConversationTurn(
                          'كلمني بهدوء وفصاحة ومعلومات دقيقة عن أغرب ظاهرة في الفضاء أو التاريخ تعرفها.',
                        ),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '🎙️ راوي وثائقي',
                        onTap: () => _processConversationTurn(
                          'قلدلي صوت راوي أفلام وثائقية عميق وهادئ واحكيلي قصة قصيرة عن أسرار الأهرامات.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Live Transcript Feed
          Expanded(
            child: _turns.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'ابدأ المكالمة أو اضغط على أي زر سريع بالأعلى\nهيظهر كلامك وردود نَبْرة ومصادر المعلومات هنا لحظة بلحظة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _transcriptScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    itemCount: _turns.length,
                    itemBuilder: (_, i) {
                      final t = _turns[i];
                      final isUser = t.role == 'user';
                      return Align(
                        alignment: isUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF10B981).withValues(alpha: 0.14)
                                : const Color(0xFF131926),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isUser
                                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                  : Colors.white12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isUser ? 'أنت' : activeVoice.name,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: isUser ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                                    ),
                                  ),
                                  if (t.emotionLabel.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      t.emotionLabel,
                                      style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                                    ),
                                  ],
                                  if (!isUser) ...[
                                    const Spacer(),
                                    InkWell(
                                      onTap: () => _speakNabraReply(
                                        t.text,
                                        voiceDirection: t.voiceDirection ?? '',
                                        isSinging: t.isSinging,
                                        imitationStyle: t.imitationStyle,
                                      ),
                                      child: const Icon(CupertinoIcons.speaker_2_fill, size: 15, color: Color(0xFFF59E0B)),
                                    ),
                                    const SizedBox(width: 10),
                                    InkWell(
                                      onTap: () => Clipboard.setData(ClipboardData(text: t.text)),
                                      child: const Icon(CupertinoIcons.doc_on_clipboard, size: 15, color: Colors.white54),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                t.text,
                                style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.55),
                              ),
                              if (t.actionBadge != null) ...[
                                const SizedBox(height: 6),
                                IosStatusPill(
                                  label: t.actionBadge!,
                                  color: TalkoraColors.iosGreen,
                                  icon: CupertinoIcons.bolt_fill,
                                ),
                              ],
                              if (t.sources.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: t.sources.map((src) {
                                    return ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('🌐 ${src.title}', style: const TextStyle(fontSize: 10.5)),
                                      onPressed: () => ref.read(nativeBridgeProvider).openUrl(src.uri),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Quick Text Input Bar during/before call
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              color: const Color(0xFF0D111A),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quickTextCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        final txt = v.trim();
                        if (txt.isEmpty) return;
                        _quickTextCtrl.clear();
                        _processConversationTurn(txt);
                      },
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك أو اطلب منه يغني أو يقلد أي صوت...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF07090F),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _isThinking
                        ? null
                        : () {
                            final txt = _quickTextCtrl.text.trim();
                            if (txt.isEmpty) return;
                            _quickTextCtrl.clear();
                            _processConversationTurn(txt);
                          },
                    child: const Text('إرسال', style: TextStyle(fontWeight: FontWeight.w800)),
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

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131926),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

class _TogglePillButton extends StatelessWidget {
  final bool active;
  final Color activeColor;
  final String label;
  final VoidCallback onTap;

  const _TogglePillButton({
    required this.active,
    required this.activeColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.16) : const Color(0xFF131926),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? activeColor.withValues(alpha: 0.7) : Colors.white12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }
}

class _NabraLiveOrbPainter extends CustomPainter {
  final double phase;
  final double level;
  final Color color;

  const _NabraLiveOrbPainter({
    required this.phase,
    required this.level,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = math.min(size.width, size.height) * 0.33;

    // Soft radial ambient halo
    final glowRadius = baseRadius + 18 + (level * 22);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowRadius));
    canvas.drawCircle(Offset(cx, cy), glowRadius, glowPaint);

    // Organic living waveform ring
    final path = Path();
    const points = 72;
    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * math.pi * 2;
      final wave1 = math.sin(angle * 4 + phase) * (2.5 + level * 14);
      final wave2 = math.cos(angle * 7 - phase * 1.4) * (1.8 + level * 8);
      final r = baseRadius + wave1 + wave2 + level * 9;
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _NabraLiveOrbPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.level != level || oldDelegate.color != color;
}

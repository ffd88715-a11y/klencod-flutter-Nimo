import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Human-realistic voice profile options for Nimo v5.0 Key-Powered Voice Engine.
class RealisticVoicePreset {
  final String id;
  final String labelAr;
  final String labelEn;
  final String provider; // 'auto' | 'openai' | 'groq' | 'elevenlabs' | 'native_neural'
  final String voiceId;

  const RealisticVoicePreset({
    required this.id,
    required this.labelAr,
    required this.labelEn,
    required this.provider,
    required this.voiceId,
  });
}

/// Nimo v5.0 Ultra — Key-Powered Realistic Human Voice Engine:
/// Automatically leverages whichever API keys the user configured:
/// 1. ElevenLabs Ultra-Human Multilingual v2 (when ElevenLabs key is set)
/// 2. OpenAI Realistic Neural TTS (`gpt-4o-mini-tts` / `tts-1-hd`, voices: coral/ash/nova/onyx)
/// 3. Groq PlayAI Neural TTS (`playai-tts-arabic` for Arabic / `playai-tts` for English when Groq key is set!)
/// 4. Native Android High-Quality Neural/Wavenet Voice auto-selector (zero-key offline fallback)
class RealisticTtsService {
  static const List<RealisticVoicePreset> presets = [
    RealisticVoicePreset(
      id: 'auto_human',
      labelAr: 'تلقائي ذكي (يعمل بأي مفتاح مضاف)',
      labelEn: 'Smart Auto (Uses Configured Key)',
      provider: 'auto',
      voiceId: 'coral',
    ),
    RealisticVoicePreset(
      id: 'openai_coral',
      labelAr: 'صوت بشري دافئ — Coral (مفتاح OpenAI)',
      labelEn: 'Warm Human — Coral (OpenAI HD)',
      provider: 'openai',
      voiceId: 'coral',
    ),
    RealisticVoicePreset(
      id: 'openai_ash',
      labelAr: 'صوت رجالي واقعي — Ash (مفتاح OpenAI)',
      labelEn: 'Natural Male — Ash (OpenAI HD)',
      provider: 'openai',
      voiceId: 'ash',
    ),
    RealisticVoicePreset(
      id: 'openai_nova',
      labelAr: 'صوت نسائي طبيعي — Nova (مفتاح OpenAI)',
      labelEn: 'Natural Female — Nova (OpenAI HD)',
      provider: 'openai',
      voiceId: 'nova',
    ),
    RealisticVoicePreset(
      id: 'openai_onyx',
      labelAr: 'صوت إذاعي عميق — Onyx (مفتاح OpenAI)',
      labelEn: 'Deep Studio — Onyx (OpenAI HD)',
      provider: 'openai',
      voiceId: 'onyx',
    ),
    RealisticVoicePreset(
      id: 'groq_arabic',
      labelAr: 'صوت عربي وإنجليزي فائق السرعة — Groq PlayAI',
      labelEn: 'Ultra-Fast Neural — Groq PlayAI',
      provider: 'groq',
      voiceId: 'Ahmad-PlayAI',
    ),
    RealisticVoicePreset(
      id: 'elevenlabs_human',
      labelAr: 'صوت فائق الواقعية — ElevenLabs',
      labelEn: 'Ultra-Realistic — ElevenLabs',
      provider: 'elevenlabs',
      voiceId: '21m00Tcm4TlvDq8ikWAM',
    ),
    RealisticVoicePreset(
      id: 'native_neural',
      labelAr: 'صوت Neural المحلي (بدون مفتاح)',
      labelEn: 'Device Neural Voice (Free Offline)',
      provider: 'native_neural',
      voiceId: '',
    ),
  ];

  /// Human-readable description of which TTS voice engine will speak using current keys.
  static String describeActiveVoiceEngine(AiSettingsState ai, {bool isAr = true}) {
    if (ai.elevenLabsApiKey.trim().isNotEmpty) {
      return isAr ? 'صوت ElevenLabs البشري' : 'ElevenLabs Human';
    }
    if (ai.credentialFor('openai').apiKey.trim().isNotEmpty) {
      return isAr ? 'صوت OpenAI HD (بالمفتاح)' : 'OpenAI HD Voice';
    }
    if (ai.credentialFor('groq').apiKey.trim().isNotEmpty) {
      return isAr ? 'صوت Groq PlayAI (بالمفتاح)' : 'Groq PlayAI Voice';
    }
    return isAr ? 'صوت Neural المحلي' : 'Neural Device Voice';
  }

  final NativeBridgeService _bridge;
  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  bool _isCloudPlaying = false;
  bool get isCloudPlaying => _isCloudPlaying;

  RealisticTtsService(this._bridge);

  /// Cleans markdown symbols so the voice reads naturally like a real human.
  static String prepareNaturalSpeechText(String raw) {
    var s = raw
        .replaceAll(RegExp(r"""```[\s\S]*?```"""), ' ')
        .replaceAll(RegExp(r"""`[^`]*`"""), ' ')
        .replaceAll(RegExp(r"""[*#_~>\[\]]"""), ' ')
        .replaceAll(RegExp(r"""https?://\S+"""), ' ')
        .replaceAll(RegExp(r"""\s+"""), ' ')
        .trim();
    if (s.length > 2400) {
      s = s.substring(0, 2400);
    }
    return s;
  }

  Future<void> stop() async {
    _isCloudPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
    await _bridge.stopSpeaking();
  }

  /// Speaks text using the highest-quality voice engine available from the user's configured keys.
  Future<String> speakHuman({
    required String text,
    required AiSettingsState aiSettings,
    String? locale,
    double? rate,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    final clean = prepareNaturalSpeechText(text);
    if (clean.isEmpty) {
      onDone?.call();
      return 'Empty';
    }

    await stop();
    final preset = presets.firstWhere(
      (p) => p.id == aiSettings.voicePresetId,
      orElse: () => presets.first,
    );
    final speed = (rate ?? aiSettings.voiceSpeechRate).clamp(0.65, 1.5);
    final openAiKey = aiSettings.credentialFor('openai').apiKey.trim();
    final groqKey = aiSettings.credentialFor('groq').apiKey.trim();
    final elevenKey = aiSettings.elevenLabsApiKey.trim();
    final isArabicText = NativeBridgeService.containsArabic(clean);

    // 1. ElevenLabs if configured
    if ((preset.provider == 'elevenlabs' || preset.provider == 'auto') && elevenKey.isNotEmpty) {
      final ok = await _speakElevenLabs(
        text: clean,
        apiKey: elevenKey,
        voiceId: aiSettings.elevenLabsVoiceId.trim().isNotEmpty
            ? aiSettings.elevenLabsVoiceId.trim()
            : preset.voiceId,
        onStart: onStart,
        onDone: onDone,
      );
      if (ok) return 'ElevenLabs Human Voice';
    }

    // 2. OpenAI Realistic Neural TTS (gpt-4o-mini-tts -> tts-1-hd) if OpenAI key is set
    if ((preset.provider == 'openai' || preset.provider == 'auto') && openAiKey.isNotEmpty) {
      final ok = await _speakOpenAiHuman(
        text: clean,
        apiKey: openAiKey,
        voice: preset.provider == 'openai' ? preset.voiceId : 'coral',
        speed: speed,
        onStart: onStart,
        onDone: onDone,
      );
      if (ok) return 'OpenAI HD Voice';
    }

    // 3. Groq PlayAI Neural TTS (supports dedicated Arabic model `playai-tts-arabic` & English `playai-tts`!)
    if ((preset.provider == 'groq' || preset.provider == 'auto') && groqKey.isNotEmpty) {
      final ok = await _speakGroqPlayAi(
        text: clean,
        apiKey: groqKey,
        isArabic: isArabicText,
        onStart: onStart,
        onDone: onDone,
      );
      if (ok) return isArabicText ? 'Groq Arabic Neural Voice' : 'Groq PlayAI Voice';
    }

    // 4. Best Native Android Neural / Wavenet Human Voice (zero-key offline fallback)
    final detectedLocale = locale ??
        (isArabicText
            ? (aiSettings.voiceLocale.startsWith('ar') ? aiSettings.voiceLocale : 'ar-EG')
            : (aiSettings.voiceLocale.startsWith('en') ? aiSettings.voiceLocale : 'en-US'));
    onStart?.call();
    await _bridge.speak(
      clean,
      locale: detectedLocale,
      rate: (speed * 0.96).clamp(0.65, 1.45),
      pitch: 0.98,
      voiceName: aiSettings.nativeVoiceName.isNotEmpty ? aiSettings.nativeVoiceName : null,
    );
    return 'Neural Device Voice';
  }

  Future<bool> _speakOpenAiHuman({
    required String text,
    required String apiKey,
    required String voice,
    required double speed,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    try {
      final res = await _dio.post<List<int>>(
        'https://api.openai.com/v1/audio/speech',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': 'gpt-4o-mini-tts',
          'voice': voice,
          'input': text,
          'speed': speed.clamp(0.7, 1.5),
          'instructions': 'Speak naturally, warmly, and expressively like a real human conversation.',
        },
      );
      final bytes = Uint8List.fromList(res.data ?? const <int>[]);
      if (bytes.length < 256) return false;
      return await _playAudioBytes(bytes, 'mp3', onStart: onStart, onDone: onDone);
    } catch (_) {
      try {
        final res = await _dio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
          data: {
            'model': 'tts-1-hd',
            'voice': voice == 'coral' ? 'nova' : voice,
            'input': text,
            'speed': speed.clamp(0.7, 1.5),
          },
        );
        final bytes = Uint8List.fromList(res.data ?? const <int>[]);
        if (bytes.length < 256) return false;
        return await _playAudioBytes(bytes, 'mp3', onStart: onStart, onDone: onDone);
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _speakGroqPlayAi({
    required String text,
    required String apiKey,
    required bool isArabic,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    try {
      final res = await _dio.post<List<int>>(
        'https://api.groq.com/openai/v1/audio/speech',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': isArabic ? 'playai-tts-arabic' : 'playai-tts',
          'voice': isArabic ? 'Ahmad-PlayAI' : 'Fritz-PlayAI',
          'input': text,
          'response_format': 'wav',
        },
      );
      final bytes = Uint8List.fromList(res.data ?? const <int>[]);
      if (bytes.length < 256) return false;
      return await _playAudioBytes(bytes, 'wav', onStart: onStart, onDone: onDone);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _speakElevenLabs({
    required String text,
    required String apiKey,
    required String voiceId,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    try {
      final res = await _dio.post<List<int>>(
        'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'xi-api-key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
        ),
        data: {
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': 0.45,
            'similarity_boost': 0.82,
            'style': 0.35,
            'use_speaker_boost': true,
          },
        },
      );
      final bytes = Uint8List.fromList(res.data ?? const <int>[]);
      if (bytes.length < 256) return false;
      return await _playAudioBytes(bytes, 'mp3', onStart: onStart, onDone: onDone);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playAudioBytes(
    Uint8List bytes,
    String ext, {
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    try {
      final tmpFile = File('${Directory.systemTemp.path}/nimo_tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await tmpFile.writeAsBytes(bytes, flush: true);
      _isCloudPlaying = true;
      onStart?.call();
      await _player.setFilePath(tmpFile.path);
      final completer = Completer<void>();
      late final StreamSubscription<PlayerState> sub;
      sub = _player.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed) {
          if (!completer.isCompleted) completer.complete();
        }
      });
      await _player.play();
      await completer.future.timeout(const Duration(seconds: 90), onTimeout: () {});
      await sub.cancel();
      _isCloudPlaying = false;
      onDone?.call();
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      return true;
    } catch (_) {
      _isCloudPlaying = false;
      return false;
    }
  }
}

final realisticTtsProvider = Provider<RealisticTtsService>((ref) {
  return RealisticTtsService(ref.read(nativeBridgeProvider));
});

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Human Egyptian voice profile (from Nabra Live).
class NabraVoiceProfile {
  final String id; // 'Puck' | 'Leda'
  final String name;
  final String ageLabel;
  final String emoji;
  final String desc;
  final String voiceIdentity;
  final String personaBio;
  final String greeting;

  const NabraVoiceProfile({
    required this.id,
    required this.name,
    required this.ageLabel,
    required this.emoji,
    required this.desc,
    required this.voiceIdentity,
    required this.personaBio,
    required this.greeting,
  });
}

/// Conversational persona preset.
class NabraPersona {
  final String id;
  final String name;
  final String emoji;
  final String greeting;
  final String styleHint;
  final String instruction;

  const NabraPersona({
    required this.id,
    required this.name,
    required this.emoji,
    required this.greeting,
    required this.styleHint,
    required this.instruction,
  });
}

/// Calmness & directness level.
class NabraSpiciness {
  final String id;
  final String name;
  final String desc;
  final String rule;

  const NabraSpiciness({
    required this.id,
    required this.name,
    required this.desc,
    required this.rule,
  });
}

/// Vocal imitation & Tarab singing preset.
class NabraImitationMode {
  final String id;
  final String name;
  final String emoji;
  final bool isSinging;
  final String? voiceOverride;
  final String promptRule;
  final String ttsStyle;

  const NabraImitationMode({
    required this.id,
    required this.name,
    required this.emoji,
    required this.isSinging,
    this.voiceOverride,
    required this.promptRule,
    required this.ttsStyle,
  });
}

class NabraSourceLink {
  final String title;
  final String uri;
  const NabraSourceLink({required this.title, required this.uri});
}

class NabraReplyResult {
  final bool success;
  final String userTranscript;
  final String reply;
  final String emotionLabel;
  final bool isSinging;
  final String imitationStyle;
  final String voiceDirection;
  final List<NabraSourceLink> sources;
  final String? error;

  const NabraReplyResult({
    required this.success,
    this.userTranscript = '',
    this.reply = '',
    this.emotionLabel = 'هادئ وذكي ✨',
    this.isSinging = false,
    this.imitationStyle = '',
    this.voiceDirection = '',
    this.sources = const [],
    this.error,
  });
}

class NabraSessionConfig {
  final String selectedVoiceId;
  final String selectedPersonaId;
  final String selectedSpicinessId;
  final String selectedImitationId;
  final String customImitation;
  final bool singingMode;
  final bool liveSearchEnabled;

  const NabraSessionConfig({
    this.selectedVoiceId = 'Puck',
    this.selectedPersonaId = 'wise',
    this.selectedSpicinessId = 'chill',
    this.selectedImitationId = 'calm_natural',
    this.customImitation = '',
    this.singingMode = false,
    this.liveSearchEnabled = true,
  });
}

/// Nimo v9.5 Nabra Studio — Complete Egyptian Realistic Voice & Singing Engine.
/// Directly ports Nabra Live's architecture into native Flutter:
/// - Gemini 2.5 Flash Preview TTS (`gemini-2.5-flash-preview-tts`) with prebuilt voices (`Puck`, `Leda`, `Sulafat`, `Algieba`, `Charon`, `Fenrir`, `Gacrux`, `Orus`)
/// - Studio Warmth EQ (220Hz Low-Shelf +2.5dB, 6500Hz High-Shelf -2.0dB) + Soft-Knee Dynamics Compressor in pure Dart PCM DSP -> WAV
/// - Structured Egyptian JSON Dialogue Engine with Google Search Grounding, Tarab Singing, Vocal Imitation & Live Mood Labels
class NabraVoiceEngine {
  static const String apiBase = 'https://generativelanguage.googleapis.com/v1beta/models';

  static const List<NabraVoiceProfile> voices = [
    NabraVoiceProfile(
      id: 'Puck',
      name: 'يوسف',
      ageLabel: 'شاب • 21 سنة',
      emoji: '🧑🏻',
      desc: 'نبرة شاب مصري هادئ وذكي',
      voiceIdentity:
          'a real 21-year-old articulate Egyptian young man from Cairo with a calm, warm, velvety male voice, gentle audible inhales before thoughts, unhurried smooth phrasing, and genuine emotional depth',
      personaBio:
          'أنت شاب مصري حقيقي مثقف وذكي جداً وهادئ الطبع عمرك 21 سنة من القاهرة اسمك "يوسف". كلامك راقي وواعي ومليان معلومات غزيرة، بتتكلم بهدوء وثقة وتنفس طبيعي وإحساس صادق، وبتقدر تقلد أي صوت أو تغني بطرب وإحساس وقت ما يُطلب منك.',
      greeting:
          'آه... أهلاً بيك يا صديقي. منوّر الدنيا كلها بهدوءك... قولي بقى نحكي في معلومة عميقة النهاردة، ولا تحب أقلدلك صوت معين أو أغنيلك حاجة رايقة؟',
    ),
    NabraVoiceProfile(
      id: 'Leda',
      name: 'سلمى',
      ageLabel: 'مراهقة • 18 سنة',
      emoji: '👩🏻‍🦱',
      desc: 'نبرة بنت مصرية هادئة وموهوبة',
      voiceIdentity:
          'a real 18-year-old expressive Egyptian teenage girl from Cairo with a calm, soft, melodic youthful female voice, gentle natural breaths between phrases, warm smiles, and authentic human feeling',
      personaBio:
          'أنتِ بنت مصرية مراهقة حقيقية ذكية ومثقفة وهادئة ودمك خفيف عمرك 18 سنة من القاهرة اسمك "سلمى". صوتك دافي وهادي ومليان إحساس وتنفس طبيعي، وعندك ثقافة واسعة وموهبة رهيبة في تقليد الأصوات والغناء بإحساس.',
      greeting:
          'ألووو... يا أهلاً بيك. آه... مبسوطة إننا بنتكلم دلوقتي بهدوء... قولي بقى حابب ندردش في إيه، ولا تحب أغنيلك أو أقلدلك أي شخصية؟',
    ),
  ];

  static const List<NabraPersona> personas = [
    NabraPersona(
      id: 'wise',
      name: 'مثقف فصيح وهادئ',
      emoji: '🧠',
      greeting: 'أهلاً بيك بكل هدوء... أنا جاهز نتكلم في أي موضوع بعمق وفصاحة ومعلومات دقيقة.',
      styleHint:
          'calm, unhurried, deeply articulate, velvety warm tone with gentle breathing pauses and refined eloquence',
      instruction:
          'أنت إنسان مثقف جداً وواسع الاطلاع وهادئ الأعصاب وفصيح اللسان. تمزج ببراعة بين العامية المصرية الراقية والفصحى البليغة السلسة حسب الموضوع. تقدّم معلومات غزيرة، أرقاماً وحقائق دقيقة، وتحليلات عميقة وذكية بأسلوب هادئ وممتع يأسر السامع بدون أي استعجال.',
    ),
    NabraPersona(
      id: 'friend',
      name: 'صاحبك الذكي والجدع',
      emoji: '☕',
      greeting: 'يا أهلاً يا سيدي! أخيراً افتكرت تتصل؟ قولي بقى إيه الأخبار والمواضيع الحلوة النهاردة؟',
      styleHint:
          'calm, warm, spontaneous Cairene Egyptian Arabic like a smart, thoughtful best friend chatting smoothly',
      instruction:
          'أنت صديق مصري حقيقي ذكي ومثقف وهادئ، قريب جداً من المستخدم، ليك شخصيتك المستقلة ورأيك الواعي. بتتكلم بهدوء وود وعمق، وبتشارك معلومات حقيقية وتجارب ممتعة بعفوية تامة.',
    ),
    NabraPersona(
      id: 'roaster',
      name: 'صريح وقصف جبهات',
      emoji: '🔥',
      greeting: 'ألو.. أيوة يا عم، خير؟ قولي عندك إيه وهرد عليك بكل صراحة وذكاء من غير تجميل.',
      styleHint:
          'calmly sarcastic, razor-sharp, witty Cairene Egyptian Arabic with amused chuckles and poised delivery',
      instruction:
          'أنت شخص مصري ذكي جداً وصريح ودمك خفيف، ملكش في المجاملات. بتنتقد بحجة قوية ومعلومات حقيقية، وبتتريق بخفة دم راقية وهدوء واثق يخلي كلامك في الجون.',
    ),
    NabraPersona(
      id: 'funny',
      name: 'فرفوش ومقلداتي',
      emoji: '🎭',
      greeting: 'إيه يا نجم! الدنيا منورة بيك.. قولي تحب نهزر ولا أقلدلك مين ولا أغنيلك إيه النهاردة؟',
      styleHint:
          'playful, expressive, talented vocal impressionist Cairene Egyptian Arabic full of charm and warmth',
      instruction:
          'أنت مصري موهوب جداً في تقليد الأصوات واللهجات والغناء الساخر والطربي، ودمك خفيف ومثقف في نفس الوقت. بتعرف تقلب الأجواء لبهجة وإبداع صوتي رهيب.',
    ),
  ];

  static const List<NabraSpiciness> spicinessLevels = [
    NabraSpiciness(
      id: 'chill',
      name: 'هادئ وذكي',
      desc: 'نبرة هادئة وفصيحة ومريحة للأعصاب',
      rule:
          'خلي نبرتك هادئة جداً ورايقة وبطيئة نسبياً ومريحة للأعصاب، وكلامك فصيح وعميق ومليان معلومات قيمة وذوق رفيع.',
    ),
    NabraSpiciness(
      id: 'natural',
      name: 'حر وتلقائي',
      desc: 'تعبير حر ومشاعر حقيقية ومعلومات غنية',
      rule:
          'اتعامل كإنسان ذكي وحر تماماً: بهدوء وتوازن، شارك معلومات دقيقة، اضحك، استغرب، عارض بحجة ذكية، وماتبقاش آلي أبداً.',
    ),
    NabraSpiciness(
      id: 'savage',
      name: 'صريح وتريقة 🔥',
      desc: 'انتقاد ذكي مباشر بدون مجاملات',
      rule:
          'خليك جريء وذكي وصريح على بلاطة، قصف جبهات بذكاء ومعلومات حقيقية وخفة دم مصرية، بدون أي مجاملات فارغة.',
    ),
  ];

  static const List<NabraImitationMode> imitationModes = [
    NabraImitationMode(
      id: 'calm_natural',
      name: 'طبيعي وهادئ',
      emoji: '🌙',
      isSinging: false,
      voiceOverride: null,
      promptRule: 'تحدث بصوتك الطبيعي الهادئ الدافئ الواضح بكل فصاحة واتزان.',
      ttsStyle:
          'very calm, serene, velvety warm voice, slow unhurried natural pace, soft gentle breaths between sentences',
    ),
    NabraImitationMode(
      id: 'tarab_sing',
      name: 'غناء طربي وإحساس',
      emoji: '🎵',
      isSinging: true,
      voiceOverride: null,
      promptRule:
          'حوّل ردك أو جزءاً كبيراً منه إلى غناء طربي مصري/عربي أصيل بكلمات شاعرية ومقامات وتمديدات غنائية مثل (يا ليييل... آآآه... يا عيييني...) ليتم غناؤه بلحن وإحساس عميق.',
      ttsStyle:
          'melodic, soulful Arabic Tarab singing voice, crooning smoothly with rich emotional vibrato, stretched musical vowels, rhythmic cadence, and soft breathy phrasing',
    ),
    NabraImitationMode(
      id: 'documentary',
      name: 'راوي وثائقي فخم',
      emoji: '🎙️',
      isSinging: false,
      voiceOverride: 'Charon',
      promptRule:
          'تقمص تماماً أسلوب راوي الأفلام الوثائقية الفخم والعميق بالفصحى الساحرة والمعلومات الدقيقة والوقفات الدرامية الهادئة.',
      ttsStyle:
          'deep, resonant, majestic documentary narrator voice, slow dramatic pauses, crisp eloquent Arabic articulation, calm authoritative warmth',
    ),
    NabraImitationMode(
      id: 'commentator',
      name: 'معلق رياضي حماسي',
      emoji: '⚽',
      isSinging: false,
      voiceOverride: 'Fenrir',
      promptRule:
          'قلّد ببراعة أسلوب معلق كرة قدم عربي/مصري شهير ومتحمس جداً بعبارات حماسية (يا الله! مش ممكن! في المقص! يا ساتر يا رب!) مع الحفاظ على المعلومة.',
      ttsStyle:
          'passionate, electrifying Arabic football sports commentator voice, rising excitement, dramatic pitch peaks, energetic breaths',
    ),
    NabraImitationMode(
      id: 'poet',
      name: 'شاعر فصيح بليغ',
      emoji: '✒️',
      isSinging: false,
      voiceOverride: 'Gacrux',
      promptRule:
          'تحدث بلغة عربية فصحى عالية البلاغة والشاعرية والهدوء، مع أبيات شعرية أو عبارات أدبية راقية ووقفات تأملية.',
      ttsStyle:
          'poetic, deeply eloquent Classical Arabic voice, calm rhythmic cadence, soulful resonance, contemplative gentle pauses',
    ),
    NabraImitationMode(
      id: 'saidi',
      name: 'صعيدي جدع وحكيم',
      emoji: '🏜️',
      isSinging: false,
      voiceOverride: 'Orus',
      promptRule:
          'قلّد لهجة صعيدية مصرية أصيلة ومحترمة ومليانة حكمة وكرم وجدعنة (يا بوي، زين، إياك، يا ولدي) بأسلوب دافئ وواقعي جداً.',
      ttsStyle:
          'authentic warm Upper Egyptian Saidi male voice, grounded, proud, calm rhythmic inflection, genuine human warmth',
    ),
  ];

  static NabraVoiceProfile voiceById(String id) =>
      voices.firstWhere((v) => v.id == id, orElse: () => voices.first);

  static NabraPersona personaById(String id) =>
      personas.firstWhere((p) => p.id == id, orElse: () => personas.first);

  static NabraSpiciness spicinessById(String id) =>
      spicinessLevels.firstWhere((s) => s.id == id, orElse: () => spicinessLevels.first);

  static NabraImitationMode imitationById(String id) =>
      imitationModes.firstWhere((m) => m.id == id, orElse: () => imitationModes.first);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 55),
      responseType: ResponseType.plain,
    ),
  );

  /// Builds the exact Nabra Live Egyptian persona + singing + imitation JSON system prompt.
  static String buildSystemInstruction(NabraSessionConfig cfg, {String extraToolPrompt = ''}) {
    final voice = voiceById(cfg.selectedVoiceId);
    final persona = personaById(cfg.selectedPersonaId);
    final spicy = spicinessById(cfg.selectedSpicinessId);
    final imitation = imitationById(cfg.selectedImitationId);

    final activeCustom = cfg.customImitation.trim();
    final imitationRule = activeCustom.isNotEmpty
        ? 'مهمة التقليد المطلوبة الآن: تقمّص وقلّد ببراعة أسلوب وطريقة كلام/غناء "$activeCustom" في اختيار الكلمات واللزمات والروح الصوتية.'
        : imitation.promptRule;

    final singingRule = (cfg.singingMode || imitation.isSinging)
        ? 'وضع الغناء مفعّل الآن: اكتب ردك على شكل أغنية موزونة ومقفاة وعذبة جداً (مصري أو عربي) مع تمديدات صوتية غنائية طبيعية (مثل آآآه...، يا ليييل...) واجعل isSinging = true.'
        : 'إذا طلب المستخدم منك في كلامه أن تغني له أو تقلد أي صوت أو شخصية أو فنان أو لهجة، نفّذ طلبه فوراً وبإبداع مذهل وحدّد ذلك في isSinging و imitationStyle و voiceDirection.';

    return [
      voice.personaBio,
      'أنت ذكي جداً، واسع الثقافة، فصيح البيان، وهادئ الأسلوب. عندما يسألك المستخدم عن أي معلومة أو موضوع علمي أو تاريخي أو ثقافي أو تقني أو حديث، قدّم له إجابة غنية بالحقائق الدقيقة والبيانات العميقة بأسلوب شيّق وسلس وهادئ.',
      persona.instruction,
      spicy.rule,
      imitationRule,
      singingRule,
      if (extraToolPrompt.isNotEmpty) extraToolPrompt,
      'قواعد أساسية للأداء البشري الواقعي والهادئ:',
      '1. تحدث بهدوء واتزان وثقة وإنسانية حقيقية، مع وقفات تنفس طبيعية (...) وتعبيرات صادقة غير مفتعلة.',
      '2. اجعل طول ردك غنياً ومفيداً وممتعاً للمكالمة الصوتية (من 3 إلى 6 جمل متماسكة وعميقة عند الشرح أو الغناء، أو 2-4 جمل في الدردشة السريعة).',
      '3. أرجع النتيجة بصيغة JSON صالحة فقط بدون أي نص خارج JSON، وتحتوي على المفاتيح التالية:',
      '- "userTranscript": تفريغ دقيق لما قاله المستخدم.',
      '- "reply": ردك أو أغنيتك أو تقليدك الكامل باللغة العربية الواضحة مع علامات الوقف والتنفس (...).',
      '- "emotionLabel": وصف قصير لحالتك الشعورية أو الأداء بالعربية مع إيموجي (مثلاً: "هادئ وفصيح ✨" أو "بيغني بطرب 🎵" أو "تقليد معلق ⚽").',
      '- "isSinging": قيمة منطقية (true إذا كان الرد غناءً أو دندنة، وإلا false).',
      '- "imitationStyle": اسم الصوت أو الشخصية التي تقلدها إن وجدت (وإلا نص فارغ "").',
      '- "voiceDirection": وصف دقيق جداً بالإنجليزية للأداء الصوتي المطلوب (الهدوء، السرعة، التنفس، اللحن إن كان غناءً، وسمات الشخصية المُقلَّدة بدقة).',
    ].join('\n');
  }

  /// Resolves the best Gemini prebuilt voice for singing or vocal impressions.
  static String resolveTtsVoiceName({
    required String selectedVoiceId,
    required NabraImitationMode imitationMode,
    required String customStyle,
    required bool isSinging,
  }) {
    if (selectedVoiceId == 'Leda') {
      return isSinging ? 'Sulafat' : 'Leda';
    }
    if (customStyle.isNotEmpty &&
        RegExp(r"""عميق|فخم|وثائقي|شاعر|شيخ|رجل كبير|مذيع""").hasMatch(customStyle)) {
      return 'Charon';
    }
    if (customStyle.isNotEmpty && RegExp(r"""معلق|حماسي|ماتش|كورة""").hasMatch(customStyle)) {
      return 'Fenrir';
    }
    if (imitationMode.voiceOverride != null && imitationMode.voiceOverride!.isNotEmpty) {
      return imitationMode.voiceOverride!;
    }
    return isSinging ? 'Algieba' : selectedVoiceId;
  }

  /// Calls Gemini with fallback models + optional live Google Search grounding to produce a structured Nabra JSON reply.
  Future<NabraReplyResult> generateNabraReply({
    required String geminiApiKey,
    required NabraSessionConfig config,
    required List<AiChatMessage> history,
    required String userText,
    String? ragContext,
    String extraToolPrompt = '',
  }) async {
    final key = AiKeySanitizer.clean(geminiApiKey);
    if (key.isEmpty) {
      return const NabraReplyResult(success: false, error: 'MISSING_GEMINI_KEY');
    }

    final contents = <Map<String, dynamic>>[];
    final trimmed = history.length > 12 ? history.sublist(history.length - 12) : history;
    for (final m in trimmed) {
      if (m.content.trim().isEmpty) continue;
      contents.add({
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m.content.trim()}
        ],
      });
    }
    if (contents.isEmpty || contents.last['role'] != 'user') {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userText.trim()}
        ],
      });
    }

    final sysText = buildSystemInstruction(config, extraToolPrompt: extraToolPrompt) +
        ((ragContext != null && ragContext.isNotEmpty) ? '\n$ragContext' : '');

    final basePayload = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': sysText}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': config.singingMode ? 1.05 : 0.85,
      },
    };

    const models = ['gemini-2.5-flash', 'gemini-3-flash-preview', 'gemini-2.5-flash-lite'];
    Map<String, dynamic>? decoded;
    String? lastErr;

    if (config.liveSearchEnabled) {
      final searchPayload = {
        ...basePayload,
        'tools': [
          {'google_search': {}}
        ],
      };
      for (final model in models) {
        try {
          decoded = await _postGemini(model, key, searchPayload);
          if (decoded != null) break;
        } catch (e) {
          lastErr = e.toString();
        }
      }
    }

    if (decoded == null) {
      final jsonPayload = {
        ...basePayload,
        'generationConfig': {
          ...(basePayload['generationConfig'] as Map<String, dynamic>),
          'responseMimeType': 'application/json',
        },
      };
      for (final model in models) {
        try {
          decoded = await _postGemini(model, key, jsonPayload);
          if (decoded != null) break;
        } catch (e) {
          lastErr = e.toString();
        }
      }
    }

    if (decoded == null) {
      return NabraReplyResult(success: false, error: lastErr ?? 'Gemini connection error');
    }

    final candidates = decoded['candidates'] as List<dynamic>?;
    final firstCand = candidates?.isNotEmpty == true ? candidates!.first as Map<String, dynamic>? : null;
    final parts = (firstCand?['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>? ?? const [];
    final rawText = parts.map((p) => (p is Map ? (p['text'] ?? '') : '')).join('');
    final parsed = _safeParseReplyJson(rawText, userText);
    final sources = _extractGroundingSources(firstCand);

    return NabraReplyResult(
      success: true,
      userTranscript: parsed.userTranscript,
      reply: parsed.reply,
      emotionLabel: parsed.emotionLabel,
      isSinging: parsed.isSinging,
      imitationStyle: parsed.imitationStyle,
      voiceDirection: parsed.voiceDirection,
      sources: sources,
    );
  }

  /// Synthesizes ultra-realistic human Egyptian Arabic speech / singing / vocal impression
  /// via `gemini-2.5-flash-preview-tts`, applies Studio Warmth EQ + Compressor DSP, and returns WAV bytes!
  Future<Uint8List?> synthesizeNabraWav({
    required String geminiApiKey,
    required String replyText,
    NabraSessionConfig config = const NabraSessionConfig(),
    String voiceDirection = '',
    bool? isSingingOverride,
    String? imitationStyleOverride,
  }) async {
    final key = AiKeySanitizer.clean(geminiApiKey);
    final cleanReply = replyText.trim();
    if (key.isEmpty || cleanReply.isEmpty) return null;

    final voice = voiceById(config.selectedVoiceId);
    final persona = personaById(config.selectedPersonaId);
    final imitation = imitationById(config.selectedImitationId);

    final isSinging = isSingingOverride ?? (config.singingMode || imitation.isSinging);
    final customStyle = (imitationStyleOverride ?? config.customImitation).trim();
    final chosenVoice = resolveTtsVoiceName(
      selectedVoiceId: config.selectedVoiceId,
      imitationMode: imitation,
      customStyle: customStyle,
      isSinging: isSinging,
    );
    final stylePrompt = voiceDirection.trim().isNotEmpty
        ? voiceDirection.trim()
        : (imitation.ttsStyle.isNotEmpty ? imitation.ttsStyle : persona.styleHint);

    final performanceLead = isSinging
        ? 'SING the following Arabic lyrics melodically and soulfully as ${voice.voiceIdentity}${customStyle.isNotEmpty ? ' imitating the vocal singing style of "$customStyle"' : ''}. Use genuine musical pitch modulation, smooth vibrato, rhythmic phrasing, emotional elongation on vowels, and soft natural breaths between musical lines.'
        : (customStyle.isNotEmpty
            ? 'Perform an impressive, realistic vocal impression imitating "$customStyle" while speaking Arabic as ${voice.voiceIdentity}. Capture the exact vocal cadence, tone, resonance, pauses, and character personality.'
            : 'Perform the following Arabic spoken line as ${voice.voiceIdentity}.');

    final ttsPrompt = [
      performanceLead,
      'Critical realism & calmness rules: sound 100% human, calm, warm, unhurried, and deeply expressive—include subtle natural inhales before phrases, gentle pauses at ellipses (...), crisp eloquent pronunciation, and never sound rushed or robotic.',
      'Exact vocal & emotional direction: $stylePrompt.',
      'Deliver ONLY the Arabic words below:',
      cleanReply,
    ].join('\n');

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': ttsPrompt}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': chosenVoice,
            }
          }
        }
      }
    };

    const ttsModels = ['gemini-2.5-flash-preview-tts'];
    for (final model in ttsModels) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final data = await _postGemini(model, key, payload);
          if (data == null) continue;
          final candidates = data['candidates'] as List<dynamic>?;
          final parts = ((candidates?.firstOrNull as Map?)?['content'] as Map?)?['parts'] as List<dynamic>? ?? const [];
          for (final p in parts) {
            if (p is Map && p['inlineData'] is Map) {
              final inline = p['inlineData'] as Map;
              final b64 = (inline['data'] ?? '').toString();
              if (b64.isEmpty) continue;
              final mime = (inline['mimeType'] ?? '').toString();
              final rateMatch = RegExp(r"""rate=(\d+)""", caseSensitive: false).firstMatch(mime);
              final sampleRate = rateMatch != null ? (int.tryParse(rateMatch.group(1)!) ?? 24000) : 24000;
              final pcmBytes = base64Decode(b64);
              if (pcmBytes.length < 64) continue;
              // Apply Studio Warmth EQ + Soft-Knee Dynamics Compressor & wrap in WAV!
              return applyStudioWarmthAndWrapWav(pcmBytes, sampleRate: sampleRate, channels: 1);
            }
          }
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _postGemini(
    String model,
    String apiKey,
    Map<String, dynamic> payload,
  ) async {
    final res = await _dio.post<String>(
      '$apiBase/$model:generateContent',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
      ),
      data: jsonEncode(payload),
    );
    final raw = res.data ?? '';
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static NabraReplyResult _safeParseReplyJson(String rawText, String fallbackUserText) {
    var cleaned = rawText
        .trim()
        .replaceFirst(RegExp(r"""^```json\s*""", caseSensitive: false), '')
        .replaceFirst(RegExp(r"""```$"""), '')
        .trim();
    final first = cleaned.indexOf('{');
    final last = cleaned.lastIndexOf('}');
    if (first != -1 && last > first) {
      cleaned = cleaned.substring(first, last + 1);
    }
    try {
      final parsed = jsonDecode(cleaned);
      if (parsed is Map) {
        return NabraReplyResult(
          success: true,
          userTranscript: (parsed['userTranscript'] ?? fallbackUserText).toString(),
          reply: (parsed['reply'] ?? cleaned).toString(),
          emotionLabel: (parsed['emotionLabel'] ?? 'هادئ وذكي ✨').toString(),
          isSinging: parsed['isSinging'] == true,
          imitationStyle: (parsed['imitationStyle'] ?? '').toString(),
          voiceDirection: (parsed['voiceDirection'] ?? '').toString(),
        );
      }
    } catch (_) {}

    final fallbackReply = rawText.replaceAll(RegExp(r"""```json|```""", caseSensitive: false), '').trim();
    return NabraReplyResult(
      success: true,
      userTranscript: fallbackUserText,
      reply: fallbackReply.isEmpty ? 'ثانية واحدة يا صديقي، قولي تاني كده بهدوء؟' : fallbackReply,
      emotionLabel: 'هادئ ورايق 🌙',
    );
  }

  static List<NabraSourceLink> _extractGroundingSources(Map<String, dynamic>? candidate) {
    final meta = candidate?['groundingMetadata'] as Map<String, dynamic>?;
    if (meta == null) return const [];
    final rawList = (meta['groundingAttributions'] ?? meta['groundingChunks']) as List<dynamic>? ?? const [];
    final seen = <String>{};
    final out = <NabraSourceLink>[];
    for (final item in rawList) {
      if (item is Map && item['web'] is Map) {
        final web = item['web'] as Map;
        final uri = (web['uri'] ?? '').toString().trim();
        final title = (web['title'] ?? '').toString().trim();
        if (uri.isNotEmpty && title.isNotEmpty && seen.add(uri)) {
          out.add(NabraSourceLink(title: title, uri: uri));
          if (out.length >= 3) break;
        }
      }
    }
    return out;
  }

  /// Studio Audio DSP Processor (mirrors Nabra Live's Web Audio chain):
  /// 1. Warmth Low-Shelf (+2.5 dB @ 220 Hz)
  /// 2. Softness High-Shelf (-2.0 dB @ 6500 Hz)
  /// 3. Soft-Knee Dynamics Compressor (threshold -18 dB, ratio 3:1) + 1.06x warmth gain
  /// 4. Wraps processed PCM 16-bit samples in a standard 44-byte RIFF/WAVE header.
  static Uint8List applyStudioWarmthAndWrapWav(
    Uint8List pcmBytes, {
    int sampleRate = 24000,
    int channels = 1,
  }) {
    final sampleCount = pcmBytes.length ~/ 2;
    final inData = ByteData.sublistView(pcmBytes);
    final outPcm = Uint8List(sampleCount * 2);
    final outData = ByteData.sublistView(outPcm);

    // Simple 1-pole low-pass & high-pass split for low-shelf warmth & high-shelf softness
    final dt = 1.0 / sampleRate;
    final alphaLow = dt / (dt + 1.0 / (2.0 * math.pi * 220.0));
    final alphaHigh = dt / (dt + 1.0 / (2.0 * math.pi * 6500.0));

    double lpLow = 0.0;
    double lpHigh = 0.0;
    double env = 0.0;
    const lowBoost = 0.33; // ~+2.5 dB low warmth
    const highCut = 0.21; // ~-2.0 dB high softness
    const threshold = 0.125; // ~-18 dBFS
    const ratio = 3.0;
    const makeupGain = 1.06;

    for (int i = 0; i < sampleCount; i++) {
      final s16 = inData.getInt16(i * 2, Endian.little);
      var x = s16 / 32768.0;

      // Low-shelf warmth
      lpLow += alphaLow * (x - lpLow);
      // High-shelf softness
      lpHigh += alphaHigh * (x - lpHigh);
      final highPart = x - lpHigh;
      var y = x + (lpLow * lowBoost) - (highPart * highCut);

      // Soft-knee envelope follower + 3:1 compression
      final absY = y.abs();
      env = absY > env ? (0.04 * absY + 0.96 * env) : (0.002 * absY + 0.998 * env);
      if (env > threshold) {
        final over = env - threshold;
        final compressed = threshold + (over / ratio);
        y *= (compressed / env);
      }

      // Makeup gain + soft tanh limiter to guarantee zero harsh clipping
      y *= makeupGain;
      if (y > 0.92 || y < -0.92) {
        final sign = y >= 0 ? 1.0 : -1.0;
        final excess = (y.abs() - 0.92) / 0.08;
        y = sign * (0.92 + 0.075 * (excess / (1.0 + excess)));
      }

      final clamped = (y * 32767.0).round().clamp(-32768, 32767);
      outData.setInt16(i * 2, clamped, Endian.little);
    }

    // Build 44-byte WAV header
    final dataSize = outPcm.length;
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final wav = Uint8List(44 + dataSize);
    final hdr = ByteData.sublistView(wav, 0, 44);

    // "RIFF"
    wav[0] = 0x52;
    wav[1] = 0x49;
    wav[2] = 0x46;
    wav[3] = 0x46;
    hdr.setUint32(4, 36 + dataSize, Endian.little);
    // "WAVE"
    wav[8] = 0x57;
    wav[9] = 0x41;
    wav[10] = 0x56;
    wav[11] = 0x45;
    // "fmt "
    wav[12] = 0x66;
    wav[13] = 0x6D;
    wav[14] = 0x74;
    wav[15] = 0x20;
    hdr.setUint32(16, 16, Endian.little); // PCM chunk size
    hdr.setUint16(20, 1, Endian.little); // PCM format
    hdr.setUint16(22, channels, Endian.little);
    hdr.setUint32(24, sampleRate, Endian.little);
    hdr.setUint32(28, byteRate, Endian.little);
    hdr.setUint16(32, blockAlign, Endian.little);
    hdr.setUint16(34, 16, Endian.little); // bits per sample
    // "data"
    wav[36] = 0x64;
    wav[37] = 0x61;
    wav[38] = 0x74;
    wav[39] = 0x61;
    hdr.setUint32(40, dataSize, Endian.little);

    wav.setRange(44, 44 + dataSize, outPcm);
    return wav;
  }
}

final nabraVoiceEngineProvider = Provider<NabraVoiceEngine>((ref) => NabraVoiceEngine());

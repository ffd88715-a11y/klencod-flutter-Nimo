import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';

/// Bulletproof API Key Sanitizer & Formatter.
/// Strips invisible Unicode RTL/LTR marks (\u200B-\u200F, \uFEFF), newlines, quotes,
/// spaces, and accidental "Bearer " or "API_KEY=" prefixes that cause HTTP header crashes.
class AiKeySanitizer {
  const AiKeySanitizer._();

  static final RegExp _prefixRe = RegExp(
    r"""^(?:bearer\s+|api[_-]?key\s*[:=]\s*|token\s*[:=]\s*)""",
    caseSensitive: false,
  );
  static final RegExp _nonAsciiHeaderSafeRe = RegExp(r"""[^\x21-\x7E]""");

  static String clean(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    while (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")) ||
            (s.startsWith('`') && s.endsWith('`')))) {
      s = s.substring(1, s.length - 1).trim();
    }
    s = s.replaceFirst(_prefixRe, '').trim();
    s = s.replaceAll(_nonAsciiHeaderSafeRe, '');
    return s;
  }

  static String mask(String raw) {
    final k = clean(raw);
    if (k.isEmpty) return '';
    if (k.length <= 10) return '${k.substring(0, 3)}***';
    return '${k.substring(0, 6)}...${k.substring(k.length - 4)}';
  }

  static bool looksLikeApiKey(String raw) {
    final k = clean(raw);
    if (k.length < 18 || k.length > 260) return false;
    return AiProviderCatalog.detectProviderFromKey(k) != null;
  }
}

/// Wire protocol family used to communicate with any AI provider.
enum AiWireFormat {
  openAiCompatible,
  googleGemini,
  anthropicClaude,
  pollinationsFree,
}

/// Built-in + Free Instant Cloud + Custom AI provider catalog (Nimo v8.0 Quantum — Live 2026 Models).
enum AiProviderType {
  pollinations,
  gemini,
  openai,
  claude,
  deepseek,
  xai,
  groq,
  openrouter,
  mistral,
  huggingface,
  ollama,
  custom,
}

class AiProviderPreset {
  final AiProviderType type;
  final String id;
  final String name;
  final String shortName;
  final String descriptionEn;
  final String descriptionAr;
  final String defaultBaseUrl;
  final String defaultModel;
  final String defaultImageModel;
  final List<String> suggestedModels;
  final AiWireFormat wireFormat;
  final bool requiresApiKey;
  final bool hasFreeTier;
  final bool supportsImageGen;
  final bool supportsVoiceTts;
  final String apiKeyPlaceholder;
  final String keyConsoleUrl;
  final List<String> keyGuideAr;
  final List<String> keyGuideEn;
  final Color badgeColor;
  final IconData icon;

  const AiProviderPreset({
    required this.type,
    required this.id,
    required this.name,
    required this.shortName,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.defaultBaseUrl,
    required this.defaultModel,
    this.defaultImageModel = '',
    required this.suggestedModels,
    required this.wireFormat,
    this.requiresApiKey = true,
    this.hasFreeTier = false,
    this.supportsImageGen = false,
    this.supportsVoiceTts = false,
    required this.apiKeyPlaceholder,
    required this.keyConsoleUrl,
    required this.keyGuideAr,
    required this.keyGuideEn,
    required this.badgeColor,
    required this.icon,
  });
}

class AiProviderCatalog {
  const AiProviderCatalog._();

  static const List<AiProviderPreset> all = [
    AiProviderPreset(
      type: AiProviderType.pollinations,
      id: 'pollinations',
      name: 'Nimo Free Cloud AI',
      shortName: 'Nimo Free',
      descriptionEn: 'Instant free AI cloud — works immediately with ZERO API key!',
      descriptionAr: 'ذكاء Nimo السحابي المجاني يعمل فوراً بدون الحاجة لأي مفتاح API!',
      defaultBaseUrl: 'https://text.pollinations.ai/openai',
      defaultModel: 'openai',
      defaultImageModel: 'flux',
      suggestedModels: ['openai', 'openai-fast', 'mistral', 'deepseek', 'qwen-coder'],
      wireFormat: AiWireFormat.pollinationsFree,
      requiresApiKey: false,
      hasFreeTier: true,
      supportsImageGen: true,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'لا يحتاج مفتاح — يعمل مجاناً فوراً',
      keyConsoleUrl: 'https://pollinations.ai',
      keyGuideAr: [
        'هذا المحرك مجاني 100% ولا يحتاج أي مفتاح API أو تسجيل حساب.',
        'يعمل فوراً في الشات والمحادثة الصوتية وتوليد الصور ومختبر البرمجة.',
        'بمجرد لصق أي مفتاح API (Gemini / OpenAI / Groq / Claude / OpenRouter / DeepSeek) يتعرف عليه Nimo ويتصل بأحدث موديل تلقائياً!',
      ],
      keyGuideEn: [
        '100% free cloud engine — no API key or sign-up required.',
        'Works immediately for Live Voice, AI Chat, Coding Lab, and automatic fallback.',
        'Paste any Gemini, OpenAI, Claude, Groq, or OpenRouter key to auto-bind the latest flagship model.',
      ],
      badgeColor: TalkoraColors.iosTeal,
      icon: CupertinoIcons.sparkles,
    ),
    AiProviderPreset(
      type: AiProviderType.gemini,
      id: 'gemini',
      name: 'Google Gemini',
      shortName: 'Gemini',
      descriptionEn: 'Live 2026 Gemini 3.8 Flash, 3.7 Flash, 3.6 Flash, 3.5 Flash & Gemini 4 + Image Gen',
      descriptionAr: 'أحدث نماذج جوجل الحية 2026: Gemini 3.8 Flash و 3.7 Flash و 3.6 Flash و Gemini 4 + توليد صور',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      defaultModel: 'gemini-3.8-flash',
      defaultImageModel: 'gemini-2.0-flash-exp-image-generation',
      suggestedModels: [
        'gemini-3.8-flash',
        'gemini-3.7-flash',
        'gemini-3.6-flash',
        'gemini-3.5-flash',
        'gemini-3.5-flash-lite',
        'gemini-4-argon',
        'gemini-4-carbon',
        'gemini-4-hydrogen',
        'gemini-3.1-pro-preview',
        'gemini-2.5-flash',
      ],
      wireFormat: AiWireFormat.googleGemini,
      hasFreeTier: true,
      supportsImageGen: true,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'AIzaSy...',
      keyConsoleUrl: 'https://aistudio.google.com/apikey',
      keyGuideAr: [
        'اضغط على "افتح صفحة المفتاح" لفتح Google AI Studio.',
        'سجّل الدخول بحساب Google ثم اضغط Create API key.',
        'انسخ المفتاح (AIzaSy...) والصقه هنا — سيتصل Nimo تلقائياً بأحدث نموذج Gemini 3.8 Flash متاح على مفتاحك!',
      ],
      keyGuideEn: [
        'Tap "Open Key Console" to visit Google AI Studio.',
        'Create an API key and paste AIzaSy... here — Nimo auto-discovers the newest Gemini 3.8 Flash model on your key!',
      ],
      badgeColor: TalkoraColors.iosBlue,
      icon: CupertinoIcons.wand_stars,
    ),
    AiProviderPreset(
      type: AiProviderType.openai,
      id: 'openai',
      name: 'OpenAI (GPT)',
      shortName: 'OpenAI',
      descriptionEn: 'Auto-connects to latest GPT-5, GPT-4.1, GPT-4o, o4-mini + GPT-Image-1 & HD Voice',
      descriptionAr: 'يتصل تلقائياً بأحدث نماذج OpenAI (GPT-5 و GPT-4.1 و GPT-4o و o4-mini) + صور وصوت بشري HD',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      defaultImageModel: 'gpt-image-1',
      suggestedModels: [
        'gpt-4o-mini',
        'gpt-4o',
        'gpt-4.1',
        'gpt-4.1-mini',
        'o4-mini',
        'o3-mini',
      ],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: false,
      supportsImageGen: true,
      supportsVoiceTts: true,
      apiKeyPlaceholder: 'sk-proj-...',
      keyConsoleUrl: 'https://platform.openai.com/api-keys',
      keyGuideAr: [
        'افتح platform.openai.com/api-keys وسجّل الدخول.',
        'اضغط "+ Create new secret key" وانسخ المفتاح (sk-proj-...).',
        'بمجرد لصقه هنا يتصل Nimo بأحدث موديل متاح ويفعّل الصوت البشري HD وتوليد الصور تلقائياً!',
      ],
      keyGuideEn: [
        'Open platform.openai.com/api-keys, create a key, and paste sk-proj-... here.',
        'Automatically unlocks latest GPT models, HD Human Voice TTS, and GPT-Image-1 / DALL-E 3!',
      ],
      badgeColor: TalkoraColors.iosGreen,
      icon: CupertinoIcons.cube_box_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.claude,
      id: 'claude',
      name: 'Anthropic Claude',
      shortName: 'Claude',
      descriptionEn: 'Auto-connects to latest Claude Sonnet 4, Claude 3.7 Sonnet & 3.5 Haiku',
      descriptionAr: 'يتصل تلقائياً بأقوى نماذج البرمجة والكتابة: Claude Sonnet 4 و 3.7 Sonnet',
      defaultBaseUrl: 'https://api.anthropic.com/v1',
      defaultModel: 'claude-sonnet-4-20250514',
      suggestedModels: [
        'claude-sonnet-4-20250514',
        'claude-3-7-sonnet-latest',
        'claude-3-5-sonnet-latest',
        'claude-3-5-haiku-latest',
      ],
      wireFormat: AiWireFormat.anthropicClaude,
      hasFreeTier: false,
      supportsImageGen: false,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'sk-ant-api03-...',
      keyConsoleUrl: 'https://console.anthropic.com/settings/keys',
      keyGuideAr: [
        'افتح console.anthropic.com/settings/keys وسجّل الدخول.',
        'اضغط "+ Create Key" وانسخ المفتاح (sk-ant-...) والصقه هنا للربط التلقائي بأحدث Claude.',
      ],
      keyGuideEn: [
        'Open console.anthropic.com/settings/keys and paste your sk-ant-... key for auto-latest model binding.',
      ],
      badgeColor: TalkoraColors.iosOrange,
      icon: CupertinoIcons.chat_bubble_2_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.deepseek,
      id: 'deepseek',
      name: 'DeepSeek AI',
      shortName: 'DeepSeek',
      descriptionEn: 'DeepSeek V3 (deepseek-chat) & DeepSeek R1 (deepseek-reasoner)',
      descriptionAr: 'نماذج DeepSeek V3 و R1 بالتفكير العميق للبرمجة والرياضيات بتكلفة رمزية',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      suggestedModels: ['deepseek-chat', 'deepseek-reasoner'],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: false,
      supportsImageGen: false,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'sk-...',
      keyConsoleUrl: 'https://platform.deepseek.com/api_keys',
      keyGuideAr: [
        'افتح platform.deepseek.com/api_keys وأنشئ مفتاحاً جديداً.',
        'اختر deepseek-chat للسرعة والذكاء أو deepseek-reasoner للتفكير العميق.',
      ],
      keyGuideEn: [
        'Visit platform.deepseek.com/api_keys and paste your key.',
      ],
      badgeColor: TalkoraColors.iosIndigo,
      icon: CupertinoIcons.compass_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.xai,
      id: 'xai',
      name: 'xAI Grok',
      shortName: 'Grok',
      descriptionEn: 'Latest Grok 3, Grok 3 Mini, Grok 2 & Grok-2-Image',
      descriptionAr: 'أحدث نماذج Grok 3 و Grok 3 Mini و Grok 2 + توليد صور Grok',
      defaultBaseUrl: 'https://api.x.ai/v1',
      defaultModel: 'grok-3-mini',
      defaultImageModel: 'grok-2-image',
      suggestedModels: ['grok-3', 'grok-3-mini', 'grok-2-latest'],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: false,
      supportsImageGen: true,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'xai-...',
      keyConsoleUrl: 'https://console.x.ai',
      keyGuideAr: [
        'افتح console.x.ai واختر API Keys ثم Create API Key.',
        'انسخ المفتاح (xai-...) والصقه هنا للربط التلقائي وتوليد الصور!',
      ],
      keyGuideEn: [
        'Visit console.x.ai -> API Keys -> Create API Key and paste xai-... here.',
      ],
      badgeColor: Color(0xFF48484A),
      icon: CupertinoIcons.flame_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.groq,
      id: 'groq',
      name: 'Groq (Ultra-Fast + Voice)',
      shortName: 'Groq',
      descriptionEn: 'Llama 3.3 70B, Llama 4 Scout & Llama 3.1 8B — ultra-fast free tier!',
      descriptionAr: 'أسرع محرك عالمياً للصوت اللايف: Llama 3.3 70B و Llama 4 + صوت عربي مجاني!',
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      suggestedModels: [
        'llama-3.3-70b-versatile',
        'llama-3.1-8b-instant',
        'meta-llama/llama-4-scout-17b-16e-instruct',
        'qwen-qwq-32b',
      ],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: true,
      supportsImageGen: false,
      supportsVoiceTts: true,
      apiKeyPlaceholder: 'gsk_...',
      keyConsoleUrl: 'https://console.groq.com/keys',
      keyGuideAr: [
        'افتح console.groq.com/keys وأنشئ مفتاحاً باسم Nimo.',
        'انسخ المفتاح (gsk_...) والصقه هنا — يفعّل أسرع محادثة صوتية وصوت عربي TTS تلقائياً!',
      ],
      keyGuideEn: [
        'Open console.groq.com/keys, create a key named Nimo, and paste gsk_... here for instant voice AI!',
      ],
      badgeColor: TalkoraColors.iosPink,
      icon: CupertinoIcons.bolt_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.openrouter,
      id: 'openrouter',
      name: 'OpenRouter (300+ Models)',
      shortName: 'OpenRouter',
      descriptionEn: 'One key for Free & Flagship Gemini, DeepSeek V3, Llama 3.3, GPT-4o & Claude',
      descriptionAr: 'مفتاح واحد لأكثر من 300 نموذج مجاني ومدفوع (Gemini, DeepSeek, GPT-4o, Claude)',
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'openrouter/free',
      defaultImageModel: 'google/gemini-2.5-flash-image-preview',
      suggestedModels: [
        'openrouter/free',
        'meta-llama/llama-3.3-70b-instruct:free',
        'deepseek/deepseek-chat-v3-0324:free',
        'google/gemini-2.5-flash',
        'openai/gpt-4o-mini',
        'anthropic/claude-sonnet-4',
      ],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: true,
      supportsImageGen: true,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'sk-or-v1-...',
      keyConsoleUrl: 'https://openrouter.ai/keys',
      keyGuideAr: [
        'افتح openrouter.ai/keys وأنشئ مفتاحاً جديداً.',
        'انسخ المفتاح (sk-or-v1-...) واستخدم openrouter/free للاتصال التلقائي بأفضل نموذج مجاني متاح!',
      ],
      keyGuideEn: [
        'Visit openrouter.ai/keys, copy sk-or-v1-... and use openrouter/free or any flagship model.',
      ],
      badgeColor: TalkoraColors.iosPurple,
      icon: CupertinoIcons.globe,
    ),
    AiProviderPreset(
      type: AiProviderType.mistral,
      id: 'mistral',
      name: 'Mistral AI',
      shortName: 'Mistral',
      descriptionEn: 'Mistral Small Latest, Mistral Large Latest & Codestral (Free tier!)',
      descriptionAr: 'أحدث نماذج Mistral Small و Large و Codestral للبرمجة (يدعم الخطة المجانية)',
      defaultBaseUrl: 'https://api.mistral.ai/v1',
      defaultModel: 'mistral-small-latest',
      suggestedModels: ['mistral-small-latest', 'mistral-large-latest', 'codestral-latest'],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: true,
      supportsImageGen: false,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'mistral-...',
      keyConsoleUrl: 'https://console.mistral.ai/api-keys',
      keyGuideAr: [
        'افتح console.mistral.ai/api-keys وفعّل الخطة المجانية ثم انسخ المفتاح.',
      ],
      keyGuideEn: [
        'Open console.mistral.ai/api-keys, enable the free tier, and copy your key.',
      ],
      badgeColor: TalkoraColors.iosTeal,
      icon: CupertinoIcons.wind,
    ),
    AiProviderPreset(
      type: AiProviderType.huggingface,
      id: 'huggingface',
      name: 'HuggingFace Hub',
      shortName: 'HuggingFace',
      descriptionEn: 'Qwen 2.5 72B, Llama 3.3 70B, DeepSeek R1 + FLUX.1 Image Generation',
      descriptionAr: 'نماذج Qwen 2.5 و Llama 3.3 المفتوحة + توليد صور FLUX.1 مجاناً',
      defaultBaseUrl: 'https://router.huggingface.co/v1',
      defaultModel: 'Qwen/Qwen2.5-72B-Instruct',
      defaultImageModel: 'black-forest-labs/FLUX.1-schnell',
      suggestedModels: [
        'Qwen/Qwen2.5-72B-Instruct',
        'meta-llama/Llama-3.3-70B-Instruct',
        'deepseek-ai/DeepSeek-R1-Distill-Qwen-32B',
      ],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: true,
      supportsImageGen: true,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'hf_...',
      keyConsoleUrl: 'https://huggingface.co/settings/tokens',
      keyGuideAr: [
        'افتح huggingface.co/settings/tokens وأنشئ Token بصلاحية Inference Providers.',
        'يدعم المحادثة والبرمجة وتوليد صور FLUX.1 مباشرة!',
      ],
      keyGuideEn: [
        'Visit huggingface.co/settings/tokens, create an Inference token (hf_...), and paste here.',
      ],
      badgeColor: TalkoraColors.iosOrange,
      icon: CupertinoIcons.smiley_fill,
    ),
    AiProviderPreset(
      type: AiProviderType.ollama,
      id: 'ollama',
      name: 'Ollama / LM Studio',
      shortName: 'Local AI',
      descriptionEn: 'Run Llama 3.2, Qwen 2.5 & DeepSeek R1 locally on your PC / LAN',
      descriptionAr: 'تشغيل Llama 3.2 و Qwen 2.5 و DeepSeek R1 محلياً على جهازك بدون مفاتيح',
      defaultBaseUrl: 'http://10.0.2.2:11434/v1',
      defaultModel: 'llama3.2',
      suggestedModels: ['llama3.2', 'qwen2.5:14b', 'deepseek-r1:14b', 'gemma2:9b'],
      wireFormat: AiWireFormat.openAiCompatible,
      requiresApiKey: false,
      hasFreeTier: true,
      supportsImageGen: false,
      supportsVoiceTts: false,
      apiKeyPlaceholder: 'Optional local key',
      keyConsoleUrl: 'https://ollama.com',
      keyGuideAr: [
        'ثبّت Ollama على جهازك وشغّل: ollama run llama3.2 ثم ضع عنوان IP الشبكة المحلية.',
      ],
      keyGuideEn: [
        'Install Ollama on your PC, run `ollama run llama3.2`, and set your LAN Base URL.',
      ],
      badgeColor: Color(0xFF636366),
      icon: CupertinoIcons.desktopcomputer,
    ),
    AiProviderPreset(
      type: AiProviderType.custom,
      id: 'custom',
      name: 'Custom Any AI API',
      shortName: 'Custom API',
      descriptionEn: 'Connect ANY OpenAI-compatible URL, chat/image model ID & API key',
      descriptionAr: 'ربط أي رابط API مخصص وأي اسم نموذج نصي أو صور وأي مفتاح بحرية كاملة',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      defaultImageModel: 'dall-e-3',
      suggestedModels: ['gpt-4o-mini', 'gpt-4o', 'gemini-3.8-flash', 'deepseek-chat'],
      wireFormat: AiWireFormat.openAiCompatible,
      hasFreeTier: false,
      supportsImageGen: true,
      supportsVoiceTts: true,
      apiKeyPlaceholder: 'Enter any API key...',
      keyConsoleUrl: 'https://openrouter.ai',
      keyGuideAr: [
        'أدخل Base URL والمفتاح وسيتعرف Nimo تلقائياً على أحدث نموذج متاح من الخادم!',
      ],
      keyGuideEn: [
        'Enter any OpenAI-compatible Base URL and API Key to auto-discover models.',
      ],
      badgeColor: TalkoraColors.iosRed,
      icon: CupertinoIcons.slider_horizontal_3,
    ),
  ];

  static AiProviderPreset byId(String id) {
    return all.firstWhere(
      (p) => p.id == id,
      orElse: () => all.first,
    );
  }

  /// Automatically identifies the AI provider from the pasted API key prefix.
  static String? detectProviderFromKey(String rawKey) {
    final k = AiKeySanitizer.clean(rawKey);
    if (k.isEmpty) return null;
    if (k.startsWith('AIza')) return 'gemini';
    if (k.startsWith('sk-ant-')) return 'claude';
    if (k.startsWith('sk-or-v1-') || k.startsWith('sk-or-')) return 'openrouter';
    if (k.startsWith('gsk_')) return 'groq';
    if (k.startsWith('xai-')) return 'xai';
    if (k.startsWith('hf_')) return 'huggingface';
    if (k.startsWith('sk-proj-') || k.startsWith('sk-svcacct-')) return 'openai';
    if (k.startsWith('sk-') && k.length >= 24) return 'openai';
    return null;
  }

  /// Only flags genuinely retired/broken model IDs (NEVER blocks live 2026 Gemini 3.x / 4.x models!).
  static bool isLegacyInvalidModel(String model) {
    final m = model.trim().toLowerCase();
    return m == 'gemini' ||
        m == 'gemini-pro' ||
        m == 'gemini-1.0-pro' ||
        m == 'google/gemini-2.0-flash-exp:free';
  }
}

/// Stored configuration for a single provider.
class ProviderCredential {
  final String apiKey;
  final String model;
  final String baseUrl;
  final List<String> discoveredModels;

  const ProviderCredential({
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.discoveredModels = const [],
  });

  ProviderCredential copyWith({
    String? apiKey,
    String? model,
    String? baseUrl,
    List<String>? discoveredModels,
  }) {
    return ProviderCredential(
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      discoveredModels: discoveredModels ?? this.discoveredModels,
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': AiKeySanitizer.clean(apiKey),
        'model': model.trim(),
        'baseUrl': baseUrl.trim(),
        'discoveredModels': discoveredModels,
      };

  factory ProviderCredential.fromJson(Map<String, dynamic> json) {
    final rawDiscovered = json['discoveredModels'];
    final discovered = rawDiscovered is List
        ? rawDiscovered.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return ProviderCredential(
      apiKey: AiKeySanitizer.clean((json['apiKey'] as String?) ?? ''),
      model: ((json['model'] as String?) ?? '').trim(),
      baseUrl: ((json['baseUrl'] as String?) ?? '').trim(),
      discoveredModels: discovered,
    );
  }
}

/// Chat message model used across Nimo AI Chat Studio, Live Voice & Roleplay Arena.
class AiChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final String? modelUsed;
  final String? imageUrl;
  final String? imageBase64;
  final String? actionBadge;
  final int? latencyMs;
  final bool isPinned;

  const AiChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.modelUsed,
    this.imageUrl,
    this.imageBase64,
    this.actionBadge,
    this.latencyMs,
    this.isPinned = false,
  });

  AiChatMessage copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    String? modelUsed,
    String? imageUrl,
    String? imageBase64,
    String? actionBadge,
    int? latencyMs,
    bool? isPinned,
  }) {
    return AiChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      modelUsed: modelUsed ?? this.modelUsed,
      imageUrl: imageUrl ?? this.imageUrl,
      imageBase64: imageBase64 ?? this.imageBase64,
      actionBadge: actionBadge ?? this.actionBadge,
      latencyMs: latencyMs ?? this.latencyMs,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'modelUsed': modelUsed,
        'imageUrl': imageUrl,
        'actionBadge': actionBadge,
        'latencyMs': latencyMs,
        'isPinned': isPinned,
      };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      role: (json['role'] as String?) ?? 'assistant',
      content: (json['content'] as String?) ?? '',
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ?? DateTime.now(),
      modelUsed: json['modelUsed'] as String?,
      imageUrl: json['imageUrl'] as String?,
      actionBadge: json['actionBadge'] as String?,
      latencyMs: (json['latencyMs'] as num?)?.toInt(),
      isPinned: json['isPinned'] == true,
    );
  }
}

/// Result of an AI request or connection test.
class AiResponseResult {
  final bool success;
  final String text;
  final String? error;
  final int latencyMs;
  final String providerName;
  final String modelName;
  final bool usedFallback;
  final String? providerId;

  const AiResponseResult({
    required this.success,
    required this.text,
    this.error,
    required this.latencyMs,
    required this.providerName,
    required this.modelName,
    this.usedFallback = false,
    this.providerId,
  });
}

/// Result of live auto-discovery of the latest available models for an API key.
class ModelDiscoveryResult {
  final bool success;
  final String latestModel;
  final List<String> availableModels;
  final String? note;

  const ModelDiscoveryResult({
    required this.success,
    required this.latestModel,
    required this.availableModels,
    this.note,
  });
}

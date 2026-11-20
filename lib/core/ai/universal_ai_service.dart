import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Nimo v7.0 Apex — Bulletproof Universal Multi-Provider AI Router.
/// Fixes every root cause of API key & model failures:
/// 1. Sanitizes every API key via `AiKeySanitizer.clean` (removes invisible RTL/LTR/zero-width/Bearer/newlines)
/// 2. Uses `ResponseType.plain` + safe JSON decoding (never crashes on text/html or text/plain errors)
/// 3. Strictly normalizes alternating user/assistant turns for Google Gemini & Anthropic Claude
/// 4. Live `/models` auto-discovery + automatic self-healing on 404/400/429/deprecated models
/// 5. Fast transient retry (502/503/504/timeout) + multi-key failover + clear Arabic diagnostics
class UniversalAiService {
  final Dio _dio;

  UniversalAiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 16),
                receiveTimeout: const Duration(seconds: 65),
                sendTimeout: const Duration(seconds: 18),
                responseType: ResponseType.plain,
                headers: const {
                  'Accept': 'application/json, text/plain, */*',
                },
              ),
            );

  /// Safely decodes Dio response data whether it arrived as Map, List, or JSON String.
  dynamic _safeDecode(dynamic data) {
    if (data is Map || data is List) return data;
    if (data is String) {
      final t = data.trim();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return jsonDecode(t);
        } catch (_) {
          return t;
        }
      }
      return t;
    }
    return data;
  }

  /// Queries the provider's live `/models` endpoint using the sanitized API key
  /// and automatically picks the newest, strongest chat model supported by that key.
  Future<ModelDiscoveryResult> discoverLatestModel({
    required String providerId,
    required String apiKey,
    String? baseUrl,
  }) async {
    final preset = AiProviderCatalog.byId(providerId);
    final key = AiKeySanitizer.clean(apiKey);
    final cleanBase = _normalizeBaseUrl(
      (baseUrl != null && baseUrl.trim().isNotEmpty) ? baseUrl.trim() : preset.defaultBaseUrl,
    );

    if (preset.wireFormat == AiWireFormat.pollinationsFree) {
      return ModelDiscoveryResult(
        success: true,
        latestModel: preset.defaultModel,
        availableModels: preset.suggestedModels,
        note: 'Nimo Free Cloud Ready',
      );
    }

    if (preset.requiresApiKey && key.isEmpty) {
      return ModelDiscoveryResult(
        success: false,
        latestModel: preset.defaultModel,
        availableModels: preset.suggestedModels,
        note: 'API key required',
      );
    }

    try {
      final liveIds = <String>[];

      if (preset.wireFormat == AiWireFormat.googleGemini) {
        final res = await _dio.get<dynamic>(
          '$cleanBase/models',
          queryParameters: {'pageSize': 100},
          options: Options(
            responseType: ResponseType.plain,
            headers: {'x-goog-api-key': key},
          ),
        );
        final decoded = _safeDecode(res.data);
        final rawList = (decoded is Map ? decoded['models'] : null) as List<dynamic>? ?? const [];
        for (final item in rawList) {
          if (item is! Map) continue;
          final methods = (item['supportedGenerationMethods'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          if (!methods.contains('generateContent')) continue;
          final rawName = (item['name'] ?? '').toString();
          final cleanId = rawName.startsWith('models/') ? rawName.substring(7) : rawName;
          if (_isUsableChatModel('gemini', cleanId)) {
            liveIds.add(cleanId);
          }
        }
      } else if (preset.wireFormat == AiWireFormat.anthropicClaude) {
        final res = await _dio.get<dynamic>(
          '$cleanBase/models',
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            },
          ),
        );
        final decoded = _safeDecode(res.data);
        final rawList = (decoded is Map ? decoded['data'] : null) as List<dynamic>? ?? const [];
        for (final item in rawList) {
          if (item is Map) {
            final id = (item['id'] ?? '').toString();
            if (_isUsableChatModel('claude', id)) liveIds.add(id);
          }
        }
      } else {
        final modelsUrl = cleanBase.endsWith('/models') ? cleanBase : '$cleanBase/models';
        final headers = <String, dynamic>{
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          if (preset.type == AiProviderType.openrouter) 'HTTP-Referer': 'https://nimo.ai',
          if (preset.type == AiProviderType.openrouter) 'X-Title': 'Nimo v7.0 Apex',
        };
        final res = await _dio.get<dynamic>(
          modelsUrl,
          options: Options(responseType: ResponseType.plain, headers: headers),
        );
        final decoded = _safeDecode(res.data);
        List<dynamic> rawList = const [];
        if (decoded is Map) {
          if (decoded['data'] is List) {
            rawList = decoded['data'] as List<dynamic>;
          } else if (decoded['models'] is List) {
            rawList = decoded['models'] as List<dynamic>;
          }
        } else if (decoded is List) {
          rawList = decoded;
        }
        for (final item in rawList) {
          String id = '';
          if (item is Map) {
            id = (item['id'] ?? item['name'] ?? '').toString();
          } else if (item is String) {
            id = item;
          }
          if (id.isNotEmpty && _isUsableChatModel(providerId, id)) {
            liveIds.add(id);
          }
        }
      }

      if (liveIds.isNotEmpty) {
        liveIds.sort((a, b) => _rankModel(providerId, b).compareTo(_rankModel(providerId, a)));
        final unique = <String>[];
        for (final m in liveIds) {
          if (!unique.contains(m)) unique.add(m);
          if (unique.length >= 16) break;
        }
        return ModelDiscoveryResult(
          success: true,
          latestModel: unique.first,
          availableModels: unique,
          note: 'Discovered ${liveIds.length} live models',
        );
      }
    } catch (_) {
      // Gracefully fall back to curated verified production models
    }

    return ModelDiscoveryResult(
      success: false,
      latestModel: preset.defaultModel,
      availableModels: preset.suggestedModels,
      note: 'Using verified latest default',
    );
  }

  static bool _isUsableChatModel(String providerId, String id) {
    final l = id.toLowerCase();
    if (l.isEmpty) return false;
    const excluded = [
      'embedding',
      'embed',
      'tts',
      'whisper',
      'audio',
      'transcribe',
      'moderation',
      'dall-e',
      'gpt-image',
      'imagen',
      'veo',
      'aqa',
      'bison',
      'gecko',
      'realtime',
      'vision-preview',
      'davinci',
      'babbage',
      'curie',
      'ada',
      'guard',
      'shield',
      'flux',
      'stable-diffusion',
      'sdxl',
      'rerank',
      'ocr',
      'robotics',
      'computer-use',
    ];
    for (final ex in excluded) {
      if (l.contains(ex)) return false;
    }
    if (providerId == 'gemini') {
      return l.startsWith('gemini-') && !l.contains('image-generation') && !l.contains('1.0');
    }
    if (providerId == 'openai') {
      return l.startsWith('gpt-') || l.startsWith('o1') || l.startsWith('o3') || l.startsWith('o4');
    }
    if (providerId == 'claude') {
      return l.startsWith('claude-');
    }
    return true;
  }

  static int _rankModel(String providerId, String id) {
    final l = id.toLowerCase();
    int score = 0;

    final ver = RegExp(r"""(\d+)(?:\.(\d+))?""").firstMatch(l);
    if (ver != null) {
      final major = int.tryParse(ver.group(1) ?? '0') ?? 0;
      final minor = int.tryParse(ver.group(2) ?? '0') ?? 0;
      if (major <= 10) {
        score += (major * 100) + (minor * 15);
      }
    }

    if (providerId == 'gemini') {
      if (l == 'gemini-2.5-flash') score += 680;
      if (l == 'gemini-2.5-flash-lite') score += 640;
      if (l == 'gemini-2.0-flash') score += 610;
      if (l.contains('2.5-pro')) score += 590;
      if (l.contains('2.5-flash') && !l.contains('lite')) score += 560;
      if (l.contains('2.0-flash') && !l.contains('lite')) score += 500;
      if (l.contains('1.5-flash')) score += 420;
      if (l.contains('exp') || l.contains('preview') || l.contains('thinking')) score -= 45;
      if (l.contains('8b')) score -= 40;
    } else if (providerId == 'openai') {
      if (l.startsWith('gpt-5')) score += 850;
      if (l == 'gpt-4.1') score += 740;
      if (l == 'gpt-4o') score += 720;
      if (l == 'gpt-4o-mini' || l == 'gpt-4.1-mini') score += 690;
      if (l.startsWith('o4-mini') || l.startsWith('o3')) score += 630;
      if (l.contains('nano') || l.contains('search') || l.contains('preview')) score -= 40;
    } else if (providerId == 'claude') {
      if (l.contains('sonnet-4') || l.contains('4-sonnet')) score += 750;
      if (l.contains('opus-4') || l.contains('4-opus')) score += 730;
      if (l.contains('3-7-sonnet')) score += 650;
      if (l.contains('3-5-sonnet')) score += 550;
      if (l.contains('latest')) score += 40;
    } else if (providerId == 'groq') {
      if (l.contains('llama-3.3-70b')) score += 720;
      if (l.contains('llama-4')) score += 690;
      if (l.contains('llama-3.1-8b')) score += 640;
      if (l.contains('qwen')) score += 540;
      if (l.contains('70b')) score += 80;
    } else if (providerId == 'deepseek') {
      if (l == 'deepseek-chat') score += 720;
      if (l == 'deepseek-reasoner') score += 650;
    } else if (providerId == 'xai') {
      if (l == 'grok-3' || l == 'grok-3-latest') score += 720;
      if (l.contains('grok-3-mini')) score += 650;
      if (l.contains('grok-2')) score += 520;
    } else if (providerId == 'openrouter') {
      if (l == 'openrouter/free') score += 800;
      if (l.endsWith(':free')) score += 350;
      if (l.contains('gemini-2.5') || l.contains('gemini-2.0')) score += 260;
      if (l.contains('deepseek-chat-v3') || l.contains('deepseek-r1')) score += 240;
      if (l.contains('llama-3.3-70b')) score += 220;
    } else if (providerId == 'mistral') {
      if (l == 'mistral-small-latest') score += 720;
      if (l == 'mistral-large-latest') score += 700;
      if (l == 'codestral-latest') score += 580;
    }

    return score;
  }

  /// Sends a multi-turn conversation with Full-Chain Model Self-Healing, Live Model Discovery & Multi-Key Failover.
  Future<AiResponseResult> sendChat({
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    String? systemPromptOverride,
    String? ragContext,
    bool allowFallback = true,
  }) async {
    final baseSys = (systemPromptOverride ?? settings.customSystemPrompt).trim();
    final qualityDirective =
        '\n[NIMO APEX QUALITY]: Deliver thorough, accurate, well-structured answers. '
        'Match the user language naturally (clear Arabic or English). Put code inside fenced markdown blocks.';
    final thinkingBoost = settings.deepThinkingEnabled
        ? '\n[DEEP THINKING MODE]: Analyze step-by-step, verify logic and edge cases, and deliver an expert-grade answer.'
        : '';
    final fullSystemPrompt = '$baseSys$qualityDirective$thinkingBoost${ragContext ?? ''}'.trim();

    // 1. Try primary active provider (with full live self-healing)
    final primaryResult = await _sendToProviderWithSelfHeal(
      providerId: settings.activeProviderId,
      settings: settings,
      messages: messages,
      systemPrompt: fullSystemPrompt,
    );

    if (primaryResult.success) {
      return primaryResult;
    }

    // 2. Smart Auto-Fallback: try all other configured providers with saved keys, then Free Cloud AI
    if (allowFallback && settings.smartFallbackEnabled) {
      final candidateIds = <String>[];
      for (final p in AiProviderCatalog.all) {
        if (p.id == settings.activeProviderId) continue;
        if (p.id == 'pollinations' || p.id == 'ollama') continue;
        final key = AiKeySanitizer.clean(settings.credentialFor(p.id).apiKey);
        if (key.isNotEmpty) {
          candidateIds.add(p.id);
        }
      }
      if (settings.activeProviderId != 'pollinations') {
        candidateIds.add('pollinations');
      }

      for (final fallbackId in candidateIds) {
        final fbResult = await _sendToProviderWithSelfHeal(
          providerId: fallbackId,
          settings: settings,
          messages: messages,
          systemPrompt: fullSystemPrompt,
        );
        if (fbResult.success) {
          return AiResponseResult(
            success: true,
            text: fbResult.text,
            latencyMs: fbResult.latencyMs,
            providerName: '${fbResult.providerName} (Auto)',
            modelName: fbResult.modelName,
            usedFallback: true,
            providerId: fallbackId,
          );
        }
      }
    }

    return primaryResult;
  }

  /// Tests a specific provider directly (with live model self-healing).
  Future<AiResponseResult> testConnection(AiSettingsState settings, {String? providerIdOverride}) {
    final targetId = providerIdOverride ?? settings.activeProviderId;
    return _sendToProviderWithSelfHeal(
      providerId: targetId,
      settings: settings,
      systemPrompt: 'Reply with: OK',
      messages: [
        AiChatMessage(
          role: 'user',
          content: 'Ping',
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  /// Tests ALL configured providers (with saved keys) in parallel for the Key Health Dashboard!
  Future<Map<String, AiResponseResult>> testAllConfiguredProviders(AiSettingsState settings) async {
    final targets = <String>[];
    for (final p in AiProviderCatalog.all) {
      if (p.id == 'ollama') continue;
      if (!p.requiresApiKey || AiKeySanitizer.clean(settings.credentialFor(p.id).apiKey).isNotEmpty) {
        targets.add(p.id);
      }
    }
    final futures = targets.map((id) async {
      final res = await testConnection(settings, providerIdOverride: id);
      return MapEntry(id, res);
    });
    final entries = await Future.wait(futures);
    return Map<String, AiResponseResult>.fromEntries(entries);
  }

  /// Tries the configured model first; if the server returns 404/400/429/model-error,
  /// automatically runs live `/models` discovery on that API key + probes curated models until one succeeds!
  Future<AiResponseResult> _sendToProviderWithSelfHeal({
    required String providerId,
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    required String systemPrompt,
  }) async {
    final preset = AiProviderCatalog.byId(providerId);
    final cred = settings.credentialFor(providerId);
    final cleanKey = AiKeySanitizer.clean(cred.apiKey);
    final rawModel = cred.model.trim();
    final initialModel = (rawModel.isEmpty || AiProviderCatalog.isLegacyInvalidModel(rawModel))
        ? preset.defaultModel
        : rawModel;

    final firstRes = await _sendWithTransientRetry(
      providerId: providerId,
      settings: settings,
      messages: messages,
      systemPrompt: systemPrompt,
      modelOverride: initialModel,
    );
    if (firstRes.success) return firstRes;

    final errLower = (firstRes.error ?? '').toLowerCase();
    // Do NOT probe other models if the API key itself is rejected (401 invalid key)
    final isAuthInvalid = errLower.contains('401') ||
        errLower.contains('invalid_api_key') ||
        errLower.contains('api key not valid') ||
        errLower.contains('api_key_invalid') ||
        errLower.contains('incorrect api key');
    if (isAuthInvalid) return firstRes;

    final shouldRetryAltModel = errLower.contains('404') ||
        errLower.contains('400') ||
        errLower.contains('429') ||
        errLower.contains('not found') ||
        errLower.contains('does not exist') ||
        errLower.contains('model') ||
        errLower.contains('decommissioned') ||
        errLower.contains('deprecated') ||
        errLower.contains('unsupported') ||
        errLower.contains('not supported');

    if (shouldRetryAltModel && (!preset.requiresApiKey || cleanKey.isNotEmpty)) {
      // Run live discovery if we don't already have discovered models
      List<String> liveDiscovered = cred.discoveredModels;
      if (liveDiscovered.isEmpty && preset.wireFormat != AiWireFormat.pollinationsFree) {
        final disc = await discoverLatestModel(
          providerId: providerId,
          apiKey: cleanKey,
          baseUrl: cred.baseUrl,
        );
        if (disc.success) liveDiscovered = disc.availableModels;
      }

      final fallbackModels = <String>[
        ...liveDiscovered,
        ...preset.suggestedModels,
      ].where((m) => m.trim().isNotEmpty && m != initialModel).toSet().take(5);

      for (final altModel in fallbackModels) {
        final retryRes = await _sendToSpecificProvider(
          providerId: providerId,
          settings: settings,
          messages: messages,
          systemPrompt: systemPrompt,
          modelOverride: altModel,
        );
        if (retryRes.success) return retryRes;
      }
    }

    return firstRes;
  }

  /// Retries once quickly on transient 502/503/504/timeout errors.
  Future<AiResponseResult> _sendWithTransientRetry({
    required String providerId,
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    required String systemPrompt,
    required String modelOverride,
  }) async {
    final res = await _sendToSpecificProvider(
      providerId: providerId,
      settings: settings,
      messages: messages,
      systemPrompt: systemPrompt,
      modelOverride: modelOverride,
    );
    if (res.success) return res;
    final err = (res.error ?? '').toLowerCase();
    final isTransient = err.contains('502') ||
        err.contains('503') ||
        err.contains('504') ||
        err.contains('timeout') ||
        err.contains('connection reset');
    if (isTransient) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return _sendToSpecificProvider(
        providerId: providerId,
        settings: settings,
        messages: messages,
        systemPrompt: systemPrompt,
        modelOverride: modelOverride,
      );
    }
    return res;
  }

  Future<AiResponseResult> _sendToSpecificProvider({
    required String providerId,
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    required String systemPrompt,
    String? modelOverride,
  }) async {
    final sw = Stopwatch()..start();
    final preset = AiProviderCatalog.byId(providerId);
    final cred = settings.credentialFor(providerId);
    final apiKey = AiKeySanitizer.clean(cred.apiKey);
    final model = (modelOverride ?? cred.model).trim().isEmpty
        ? preset.defaultModel
        : (modelOverride ?? cred.model).trim();
    final baseUrl = _normalizeBaseUrl(
      cred.baseUrl.trim().isEmpty ? preset.defaultBaseUrl : cred.baseUrl.trim(),
    );

    if (preset.requiresApiKey && apiKey.isEmpty) {
      sw.stop();
      return AiResponseResult(
        success: false,
        text: '',
        error: 'MISSING_API_KEY',
        latencyMs: sw.elapsedMilliseconds,
        providerName: preset.shortName,
        modelName: model,
        providerId: providerId,
      );
    }

    try {
      String replyText;
      switch (preset.wireFormat) {
        case AiWireFormat.pollinationsFree:
          replyText = await _callPollinationsFree(
            baseUrl: baseUrl,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            temperature: settings.temperature,
          );
          break;
        case AiWireFormat.googleGemini:
          replyText = await _callGemini(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
          );
          break;
        case AiWireFormat.anthropicClaude:
          replyText = await _callClaude(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
          );
          break;
        case AiWireFormat.openAiCompatible:
          replyText = await _callOpenAiCompatible(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            isOpenRouter: preset.type == AiProviderType.openrouter,
          );
          break;
      }

      sw.stop();
      return AiResponseResult(
        success: true,
        text: replyText.trim(),
        latencyMs: sw.elapsedMilliseconds,
        providerName: preset.shortName,
        modelName: model,
        providerId: providerId,
      );
    } on DioException catch (e) {
      sw.stop();
      final status = e.response?.statusCode;
      final serverMsg = _extractErrorMessage(_safeDecode(e.response?.data)) ?? e.message ?? 'Network error';
      final friendly = _friendlyError(status, serverMsg);
      return AiResponseResult(
        success: false,
        text: '',
        error: friendly,
        latencyMs: sw.elapsedMilliseconds,
        providerName: preset.shortName,
        modelName: model,
        providerId: providerId,
      );
    } catch (e) {
      sw.stop();
      return AiResponseResult(
        success: false,
        text: '',
        error: e.toString(),
        latencyMs: sw.elapsedMilliseconds,
        providerName: preset.shortName,
        modelName: model,
        providerId: providerId,
      );
    }
  }

  /// Normalizes chat turns so messages ALWAYS start with 'user', have non-empty text,
  /// and strictly alternate 'user' / 'assistant' (required by Gemini & Claude APIs!).
  List<Map<String, String>> _normalizeStrictTurns(List<AiChatMessage> messages) {
    final turns = <Map<String, String>>[];
    for (final m in messages) {
      if (m.role != 'user' && m.role != 'assistant') continue;
      final txt = m.content.trim();
      if (txt.isEmpty) continue;
      if (turns.isEmpty && m.role != 'user') continue;
      if (turns.isNotEmpty && turns.last['role'] == m.role) {
        turns.last['content'] = '${turns.last['content']}\n\n$txt';
      } else {
        turns.add({'role': m.role, 'content': txt});
      }
    }
    if (turns.isEmpty) {
      turns.add({'role': 'user', 'content': 'Hello'});
    }
    return turns;
  }

  String _friendlyError(int? status, String raw) {
    if (status == 400) {
      return 'HTTP 400 (طلب غير متوافق أو اسم نموذج غير مدعوم): $raw';
    }
    if (status == 401) {
      return 'HTTP 401 (المفتاح غير صحيح أو منتهي الصلاحية — تأكد من نسخه كاملاً): $raw';
    }
    if (status == 402) {
      return 'HTTP 402 (الرصيد غير كافٍ في حساب API): $raw';
    }
    if (status == 403) {
      return 'HTTP 403 (صلاحية المفتاح مرفوضة أو الخدمة مقيدة في منطقتك): $raw';
    }
    if (status == 404) {
      return 'HTTP 404 (النموذج غير موجود على هذا المفتاح — جرب تحديث النماذج): $raw';
    }
    if (status == 429) {
      return 'HTTP 429 (تم تجاوز الحد المجاني مؤقتاً — انتظر ثوانٍ أو أضف مفتاحاً آخر): $raw';
    }
    if (status != null) {
      return 'HTTP $status: $raw';
    }
    final low = raw.toLowerCase();
    if (low.contains('socketexception') || low.contains('failed host lookup')) {
      return 'لا يوجد اتصال بالإنترنت أو تعذّر الوصول للخادم: $raw';
    }
    if (low.contains('timeout')) {
      return 'انتهت مهلة الاتصال بالخادم — تأكد من سرعة الإنترنت وحاول مجدداً.';
    }
    return raw;
  }

  Future<String> _callPollinationsFree({
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    required double temperature,
  }) async {
    final trimmedSys = systemPrompt.length > 1200 ? systemPrompt.substring(0, 1200) : systemPrompt;
    final payloadMessages = <Map<String, String>>[
      if (trimmedSys.isNotEmpty) {'role': 'system', 'content': trimmedSys},
      for (final m in messages)
        if ((m.role == 'user' || m.role == 'assistant') && m.content.trim().isNotEmpty)
          {'role': m.role, 'content': m.content.trim()},
    ];

    final modelsToTry = <String>[model, if (model != 'openai') 'openai', 'mistral'];
    for (final mName in modelsToTry) {
      try {
        final res = await _dio.post<dynamic>(
          baseUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: const {'Content-Type': 'application/json'},
          ),
          data: jsonEncode({
            'model': mName,
            'messages': payloadMessages,
            'temperature': temperature,
            'private': true,
          }),
        );
        final data = _safeDecode(res.data);
        if (data is Map) {
          final choices = data['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final msg = (choices.first as Map)['message'] as Map?;
            final content = msg?['content'];
            if (content is String && content.trim().isNotEmpty) return content;
          }
        } else if (data is String && data.trim().isNotEmpty && !data.trimLeft().startsWith('<')) {
          return data;
        }
      } catch (_) {}
    }

    // Resilient GET fallback with capped URI length
    final lastUser = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => AiChatMessage(role: 'user', content: 'Hello', timestamp: DateTime.now()),
    );
    final shortUser = lastUser.content.length > 500 ? lastUser.content.substring(0, 500) : lastUser.content;
    final encoded = Uri.encodeComponent(shortUser);
    final sysEnc = Uri.encodeComponent(
      trimmedSys.length > 260 ? trimmedSys.substring(0, 260) : trimmedSys,
    );
    final seed = Random().nextInt(999999);
    final res = await _dio.get<String>(
      'https://text.pollinations.ai/$encoded?model=openai&seed=$seed&system=$sysEnc',
      options: Options(responseType: ResponseType.plain),
    );
    if (res.data != null && res.data!.trim().isNotEmpty && !res.data!.trimLeft().startsWith('<')) {
      return res.data!;
    }
    throw Exception('Free Cloud AI did not return a response.');
  }

  Future<String> _callOpenAiCompatible({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    required double temperature,
    required int maxTokens,
    required bool isOpenRouter,
  }) async {
    final endpoint = baseUrl.endsWith('/chat/completions') ? baseUrl : '$baseUrl/chat/completions';
    final payloadMessages = <Map<String, String>>[
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      for (final m in messages)
        if ((m.role == 'user' || m.role == 'assistant') && m.content.trim().isNotEmpty)
          {'role': m.role, 'content': m.content.trim()},
    ];

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      if (isOpenRouter) 'HTTP-Referer': 'https://nimo.ai',
      if (isOpenRouter) 'X-Title': 'Nimo v7.0 Apex',
    };

    final isReasoningModel = model.startsWith('o1') || model.startsWith('o3') || model.startsWith('o4');
    final body = <String, dynamic>{
      'model': model,
      'messages': payloadMessages,
      if (!isReasoningModel) 'temperature': temperature,
      if (isReasoningModel) 'max_completion_tokens': maxTokens else 'max_tokens': maxTokens,
    };

    final res = await _dio.post<dynamic>(
      endpoint,
      options: Options(responseType: ResponseType.plain, headers: headers),
      data: jsonEncode(body),
    );

    final data = _safeDecode(res.data);
    if (data is Map) {
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final msg = (choices.first as Map)['message'] as Map?;
        final content = msg?['content'];
        if (content is String && content.isNotEmpty) return content;
        // Support array content parts (some OpenAI-compatible gateways)
        if (content is List) {
          final buf = StringBuffer();
          for (final part in content) {
            if (part is Map && part['text'] is String) buf.write(part['text']);
          }
          if (buf.isNotEmpty) return buf.toString();
        }
        // Support reasoning_content fallback (DeepSeek Reasoner / Qwen)
        final reasoning = msg?['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) return reasoning;
      }
    }
    throw Exception('Empty response from OpenAI-compatible API.');
  }

  Future<String> _callGemini({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    required double temperature,
    required int maxTokens,
  }) async {
    final cleanModel = model.startsWith('models/') ? model.substring(7) : model;
    final endpoint = '$baseUrl/models/$cleanModel:generateContent';
    final isV1Beta = baseUrl.contains('v1beta');

    final strictTurns = _normalizeStrictTurns(messages);
    final contents = <Map<String, dynamic>>[
      for (int i = 0; i < strictTurns.length; i++)
        {
          'role': strictTurns[i]['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {
              'text': (!isV1Beta && i == 0 && systemPrompt.isNotEmpty)
                  ? '$systemPrompt\n\n${strictTurns[i]['content']}'
                  : strictTurns[i]['content'],
            }
          ],
        },
    ];

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
      if (isV1Beta && systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ],
        },
    };

    final res = await _dio.post<dynamic>(
      endpoint,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
      ),
      data: jsonEncode(body),
    );

    final data = _safeDecode(res.data);
    if (data is Map) {
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = (candidates.first as Map)['content'] as Map?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          final buffer = StringBuffer();
          for (final p in parts) {
            if (p is Map) {
              final txt = p['text'] as String?;
              if (txt != null) buffer.write(txt);
            }
          }
          if (buffer.isNotEmpty) return buffer.toString();
        }
      }
      final blockReason = (data['promptFeedback'] as Map?)?['blockReason'];
      if (blockReason != null) {
        throw Exception('Gemini blocked prompt: $blockReason');
      }
    }
    throw Exception('Empty response from Google Gemini API.');
  }

  Future<String> _callClaude({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    required double temperature,
    required int maxTokens,
  }) async {
    final endpoint = baseUrl.endsWith('/messages') ? baseUrl : '$baseUrl/messages';
    final claudeMessages = _normalizeStrictTurns(messages);

    final res = await _dio.post<dynamic>(
      endpoint,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
      ),
      data: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'temperature': temperature,
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        'messages': claudeMessages,
      }),
    );

    final data = _safeDecode(res.data);
    if (data is Map) {
      final contentList = data['content'] as List<dynamic>?;
      if (contentList != null && contentList.isNotEmpty) {
        final buffer = StringBuffer();
        for (final item in contentList) {
          if (item is Map && item['type'] == 'text') {
            buffer.write(item['text'] ?? '');
          }
        }
        if (buffer.isNotEmpty) return buffer.toString();
      }
    }
    throw Exception('Empty response from Anthropic Claude API.');
  }

  String _normalizeBaseUrl(String raw) {
    var clean = raw.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        return (err['message'] ?? err['type'] ?? err.toString()).toString();
      }
      if (err is String) return err;
      if (data['message'] is String) return data['message'] as String;
    } else if (data is String && data.isNotEmpty) {
      return data.length > 220 ? '${data.substring(0, 220)}...' : data;
    }
    return null;
  }
}

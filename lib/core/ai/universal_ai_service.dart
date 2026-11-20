import 'dart:async';
import 'package:dio/dio.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Nimo v5.0 Ultra — Universal Multi-Provider AI Router with Live Latest-Model Auto-Discovery,
/// Model Self-Healing, Transient Retry, Smart Multi-Key Fallback & Unified RAG Injection.
class UniversalAiService {
  final Dio _dio;

  UniversalAiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 22),
                receiveTimeout: const Duration(seconds: 75),
              ),
            );

  /// Queries the provider's live `/models` endpoint using the user's API key
  /// and automatically picks the newest, strongest chat model supported by that key.
  Future<ModelDiscoveryResult> discoverLatestModel({
    required String providerId,
    required String apiKey,
    String? baseUrl,
  }) async {
    final preset = AiProviderCatalog.byId(providerId);
    final key = apiKey.trim();
    final cleanBase = _normalizeBaseUrl(
      (baseUrl != null && baseUrl.trim().isNotEmpty) ? baseUrl.trim() : preset.defaultBaseUrl,
    );

    if (preset.wireFormat == AiWireFormat.pollinationsFree) {
      return ModelDiscoveryResult(
        success: true,
        latestModel: preset.defaultModel,
        availableModels: preset.suggestedModels,
        note: 'Pollinations Free Cloud',
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
      List<String> liveIds = [];

      if (preset.wireFormat == AiWireFormat.googleGemini) {
        final res = await _dio.get<Map<String, dynamic>>(
          '$cleanBase/models',
          queryParameters: {'pageSize': 100},
          options: Options(headers: {'x-goog-api-key': key}),
        );
        final rawList = (res.data?['models'] as List<dynamic>?) ?? const [];
        for (final item in rawList) {
          if (item is! Map<String, dynamic>) continue;
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
        final res = await _dio.get<Map<String, dynamic>>(
          '$cleanBase/models',
          options: Options(
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            },
          ),
        );
        final rawList = (res.data?['data'] as List<dynamic>?) ?? const [];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final id = (item['id'] ?? '').toString();
            if (_isUsableChatModel('claude', id)) liveIds.add(id);
          }
        }
      } else {
        final modelsUrl = cleanBase.endsWith('/models') ? cleanBase : '$cleanBase/models';
        final headers = <String, dynamic>{
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          if (preset.type == AiProviderType.openrouter) 'HTTP-Referer': 'https://nimo.ai',
          if (preset.type == AiProviderType.openrouter) 'X-Title': 'Nimo v5.0 Ultra',
        };
        final res = await _dio.get<dynamic>(modelsUrl, options: Options(headers: headers));
        final data = res.data;
        List<dynamic> rawList = const [];
        if (data is Map<String, dynamic>) {
          if (data['data'] is List) {
            rawList = data['data'] as List<dynamic>;
          } else if (data['models'] is List) {
            rawList = data['models'] as List<dynamic>;
          }
        } else if (data is List) {
          rawList = data;
        }
        for (final item in rawList) {
          String id = '';
          if (item is Map<String, dynamic>) {
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
      // Fall back to curated real latest model catalog if /models is restricted
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

    // Extract major.minor version numbers to prefer newest generations
    final ver = RegExp(r"""(\d+)(?:\.(\d+))?""").firstMatch(l);
    if (ver != null) {
      final major = int.tryParse(ver.group(1) ?? '0') ?? 0;
      final minor = int.tryParse(ver.group(2) ?? '0') ?? 0;
      if (major <= 10) {
        score += (major * 100) + (minor * 15);
      }
    }

    if (providerId == 'gemini') {
      if (l.contains('2.5-flash') && !l.contains('lite') && !l.contains('preview')) score += 600;
      if (l.contains('2.5-pro')) score += 580;
      if (l.contains('2.5-flash')) score += 540;
      if (l.contains('2.0-flash') && !l.contains('lite')) score += 450;
      if (l.contains('latest')) score += 60;
      if (l.contains('exp') || l.contains('preview')) score -= 35;
      if (l.contains('lite') || l.contains('8b')) score -= 40;
    } else if (providerId == 'openai') {
      if (l == 'gpt-4.1') score += 700;
      if (l == 'gpt-4o') score += 680;
      if (l.startsWith('gpt-5')) score += 850;
      if (l.startsWith('gpt-4.5')) score += 760;
      if (l.startsWith('gpt-4.1-mini')) score += 610;
      if (l.startsWith('o4-mini') || l.startsWith('o3')) score += 620;
      if (l.contains('mini')) score -= 25;
      if (l.contains('nano')) score -= 40;
      if (l.contains('search') || l.contains('preview')) score -= 30;
    } else if (providerId == 'claude') {
      if (l.contains('sonnet-4') || l.contains('4-sonnet')) score += 750;
      if (l.contains('opus-4') || l.contains('4-opus')) score += 730;
      if (l.contains('3-7-sonnet')) score += 650;
      if (l.contains('3-5-sonnet')) score += 550;
      if (l.contains('latest')) score += 40;
    } else if (providerId == 'groq') {
      if (l.contains('llama-4')) score += 700;
      if (l.contains('llama-3.3-70b')) score += 660;
      if (l.contains('qwen')) score += 540;
      if (l.contains('70b')) score += 100;
      if (l.contains('8b')) score -= 40;
    } else if (providerId == 'deepseek') {
      if (l == 'deepseek-chat') score += 700;
      if (l == 'deepseek-reasoner') score += 650;
    } else if (providerId == 'xai') {
      if (l == 'grok-3' || l == 'grok-3-latest') score += 720;
      if (l.contains('grok-3-mini')) score += 620;
      if (l.contains('grok-2')) score += 520;
    } else if (providerId == 'openrouter') {
      if (l.endsWith(':free')) score += 350;
      if (l.contains('gemini-2.5') || l.contains('gemini-2.0')) score += 260;
      if (l.contains('deepseek-chat-v3') || l.contains('deepseek-r1')) score += 240;
      if (l.contains('llama-3.3-70b')) score += 220;
    } else if (providerId == 'mistral') {
      if (l == 'mistral-large-latest') score += 700;
      if (l == 'mistral-small-latest') score += 600;
      if (l == 'codestral-latest') score += 580;
    }

    return score;
  }

  /// Sends a multi-turn conversation with Model Self-Healing, Smart Routing & Automatic Fallback.
  Future<AiResponseResult> sendChat({
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    String? systemPromptOverride,
    String? ragContext,
    bool allowFallback = true,
  }) async {
    final baseSys = (systemPromptOverride ?? settings.customSystemPrompt).trim();
    final qualityDirective =
        '\n[NIMO ULTRA QUALITY PROTOCOL]: Deliver rich, thorough, accurate, well-structured responses. '
        'Match the user language naturally (clear Arabic or English). When writing code, provide complete, clean, runnable code in fenced markdown blocks.';
    final thinkingBoost = settings.deepThinkingEnabled
        ? '\n[DEEP THINKING MODE]: Break down the problem step-by-step, verify edge cases and accuracy, and deliver an expert-grade answer.'
        : '';
    final fullSystemPrompt = '$baseSys$qualityDirective$thinkingBoost${ragContext ?? ''}'.trim();

    // 1. Try primary active provider (with automatic model self-healing if model ID returns 404)
    final primaryResult = await _sendToProviderWithSelfHeal(
      providerId: settings.activeProviderId,
      settings: settings,
      messages: messages,
      systemPrompt: fullSystemPrompt,
    );

    if (primaryResult.success) {
      return primaryResult;
    }

    // 2. Smart Auto-Fallback: try other configured providers with keys, then Free Cloud AI
    if (allowFallback && settings.smartFallbackEnabled) {
      final candidateIds = <String>[];
      for (final p in AiProviderCatalog.all) {
        if (p.id == settings.activeProviderId) continue;
        if (p.id == 'pollinations' || p.id == 'ollama') continue;
        final key = settings.credentialFor(p.id).apiKey.trim();
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
          );
        }
      }
    }

    return primaryResult;
  }

  /// Tests a specific provider directly (with automatic latest-model self-healing on 404).
  Future<AiResponseResult> testConnection(AiSettingsState settings, {String? providerIdOverride}) {
    final targetId = providerIdOverride ?? settings.activeProviderId;
    return _sendToProviderWithSelfHeal(
      providerId: targetId,
      settings: settings,
      systemPrompt: 'Reply with only: OK - Connected!',
      messages: [
        AiChatMessage(
          role: 'user',
          content: 'Ping',
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  /// Tries the user's configured model first; if the server reports 404 / model_not_found,
  /// automatically tries the provider's verified latest fallback models.
  Future<AiResponseResult> _sendToProviderWithSelfHeal({
    required String providerId,
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    required String systemPrompt,
  }) async {
    final preset = AiProviderCatalog.byId(providerId);
    final cred = settings.credentialFor(providerId);
    final rawModel = cred.model.trim();
    final initialModel = (rawModel.isEmpty || AiProviderCatalog.isLegacyInvalidModel(rawModel))
        ? preset.defaultModel
        : rawModel;

    final firstRes = await _sendToSpecificProvider(
      providerId: providerId,
      settings: settings,
      messages: messages,
      systemPrompt: systemPrompt,
      modelOverride: initialModel,
    );
    if (firstRes.success) return firstRes;

    final errLower = (firstRes.error ?? '').toLowerCase();
    final isModelErr = errLower.contains('404') ||
        errLower.contains('not found') ||
        errLower.contains('does not exist') ||
        errLower.contains('model') ||
        errLower.contains('decommissioned') ||
        errLower.contains('deprecated');

    if (isModelErr && preset.requiresApiKey && cred.apiKey.trim().isNotEmpty) {
      final fallbackModels = <String>[
        ...cred.discoveredModels,
        ...preset.suggestedModels,
      ].where((m) => m != initialModel).toSet().take(3);

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
    final apiKey = cred.apiKey.trim();
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
      );
    } on DioException catch (e) {
      sw.stop();
      final status = e.response?.statusCode;
      final serverMsg = _extractErrorMessage(e.response?.data) ?? e.message ?? 'Network error';
      return AiResponseResult(
        success: false,
        text: '',
        error: status != null ? 'HTTP $status: $serverMsg' : serverMsg,
        latencyMs: sw.elapsedMilliseconds,
        providerName: preset.shortName,
        modelName: model,
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
      );
    }
  }

  Future<String> _callPollinationsFree({
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    required double temperature,
  }) async {
    final payloadMessages = <Map<String, String>>[
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      for (final m in messages)
        if (m.role == 'user' || m.role == 'assistant') {'role': m.role, 'content': m.content},
    ];

    try {
      final res = await _dio.post<dynamic>(
        baseUrl,
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {
          'model': model,
          'messages': payloadMessages,
          'temperature': temperature,
          'private': true,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
          final content = msg?['content'];
          if (content is String && content.trim().isNotEmpty) return content;
        }
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
    } catch (_) {
      final lastUser = messages.lastWhere(
        (m) => m.role == 'user',
        orElse: () => AiChatMessage(role: 'user', content: 'Hello', timestamp: DateTime.now()),
      );
      final encoded = Uri.encodeComponent(lastUser.content);
      final sysEnc = Uri.encodeComponent(
        systemPrompt.length > 420 ? systemPrompt.substring(0, 420) : systemPrompt,
      );
      final res = await _dio.get<String>(
        'https://text.pollinations.ai/$encoded?model=$model&system=$sysEnc',
        options: Options(responseType: ResponseType.plain),
      );
      if (res.data != null && res.data!.trim().isNotEmpty) {
        return res.data!;
      }
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
        if (m.role == 'user' || m.role == 'assistant') {'role': m.role, 'content': m.content},
    ];

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      if (isOpenRouter) 'HTTP-Referer': 'https://nimo.ai',
      if (isOpenRouter) 'X-Title': 'Nimo v5.0 Ultra',
    };

    final isReasoningModel = model.startsWith('o1') || model.startsWith('o3') || model.startsWith('o4');
    final body = <String, dynamic>{
      'model': model,
      'messages': payloadMessages,
      if (!isReasoningModel) 'temperature': temperature,
      if (isReasoningModel) 'max_completion_tokens': maxTokens else 'max_tokens': maxTokens,
    };

    final res = await _dio.post<Map<String, dynamic>>(
      endpoint,
      options: Options(headers: headers),
      data: body,
    );

    final data = res.data ?? <String, dynamic>{};
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final content = msg?['content'];
      if (content is String && content.isNotEmpty) return content;
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

    final contents = <Map<String, dynamic>>[
      for (final m in messages)
        if (m.role == 'user' || m.role == 'assistant')
          {
            'role': m.role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m.content}
            ],
          },
    ];

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
      if (systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ],
        },
    };

    final res = await _dio.post<Map<String, dynamic>>(
      endpoint,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
      ),
      data: body,
    );

    final data = res.data ?? <String, dynamic>{};
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts != null && parts.isNotEmpty) {
        final buffer = StringBuffer();
        for (final p in parts) {
          final txt = (p as Map<String, dynamic>)['text'] as String?;
          if (txt != null) buffer.write(txt);
        }
        if (buffer.isNotEmpty) return buffer.toString();
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
    final claudeMessages = <Map<String, String>>[
      for (final m in messages)
        if (m.role == 'user' || m.role == 'assistant') {'role': m.role, 'content': m.content},
    ];

    final res = await _dio.post<Map<String, dynamic>>(
      endpoint,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
      ),
      data: {
        'model': model,
        'max_tokens': maxTokens,
        'temperature': temperature,
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        'messages': claudeMessages,
      },
    );

    final data = res.data ?? <String, dynamic>{};
    final contentList = data['content'] as List<dynamic>?;
    if (contentList != null && contentList.isNotEmpty) {
      final buffer = StringBuffer();
      for (final item in contentList) {
        if (item is Map<String, dynamic> && item['type'] == 'text') {
          buffer.write(item['text'] ?? '');
        }
      }
      if (buffer.isNotEmpty) return buffer.toString();
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
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        return (err['message'] ?? err['type'] ?? err.toString()).toString();
      }
      if (err is String) return err;
      if (data['message'] is String) return data['message'] as String;
    } else if (data is String && data.isNotEmpty) {
      return data.length > 200 ? '${data.substring(0, 200)}...' : data;
    }
    return null;
  }
}

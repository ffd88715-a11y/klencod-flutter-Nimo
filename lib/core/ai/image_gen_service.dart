import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/universal_ai_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

class GeneratedImageItem {
  final String id;
  final String prompt;
  final String enhancedPrompt;
  final String style;
  final String engine;
  final String imageUrl;
  final String? localPath;
  final String? base64Bytes;
  final DateTime createdAt;

  const GeneratedImageItem({
    required this.id,
    required this.prompt,
    this.enhancedPrompt = '',
    required this.style,
    required this.engine,
    required this.imageUrl,
    this.localPath,
    this.base64Bytes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'enhancedPrompt': enhancedPrompt,
        'style': style,
        'engine': engine,
        'imageUrl': imageUrl,
        'localPath': localPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GeneratedImageItem.fromJson(Map<String, dynamic> json) {
    return GeneratedImageItem(
      id: (json['id'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      enhancedPrompt: (json['enhancedPrompt'] ?? '').toString(),
      style: (json['style'] ?? 'realistic').toString(),
      engine: (json['engine'] ?? 'Nimo Image Engine').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      localPath: json['localPath'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

class ImageGenResult {
  final bool success;
  final GeneratedImageItem? item;
  final Uint8List? bytes;
  final String? error;
  final bool usedFallback;

  const ImageGenResult({
    required this.success,
    this.item,
    this.bytes,
    this.error,
    this.usedFallback = false,
  });
}

/// Nimo v5.0 Ultra — Upgraded Multi-Engine AI Image Generation Studio:
/// - Auto-translates Arabic prompts into rich cinematic English using the user's active AI key
/// - Real production image endpoints:
///   1) Google Gemini (`gemini-2.0-flash-exp-image-generation` / `gemini-2.5-flash-image-preview` / `imagen-3.0-generate-002`)
///   2) OpenAI (`gpt-image-1` -> `dall-e-3` HD -> `dall-e-2`)
///   3) xAI Grok (`grok-2-image`)
///   4) HuggingFace Inference Router (`FLUX.1-schnell` -> `SDXL`)
///   5) OpenRouter (`google/gemini-2.5-flash-image-preview`)
///   6) Pollinations Pro Free Multi-Model (`flux`, `flux-realism`, `flux-anime`, `flux-3d`, `turbo`) with automatic retry
/// - Persists generated images locally so gallery thumbnails ALWAYS load even for base64 engines!
class ImageGenService {
  static const _kHistoryKey = 'nimo_generated_images_v5';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 28),
      receiveTimeout: const Duration(seconds: 95),
    ),
  );

  static const Map<String, String> styleSuffixes = {
    'realistic': 'ultra realistic 8k photography, natural cinematic lighting, sharp focus, shot on 35mm DSLR, rich textures',
    'cinematic': 'cinematic movie still, dramatic volumetric lighting, anamorphic lens, film grain, 8k',
    'anime': 'masterpiece Japanese anime illustration, crisp cel shading, expressive lighting, studio quality',
    '3d': '3D Unreal Engine 5 render, Octane render, soft studio reflections, global illumination, 8k',
    'logo': 'minimalist modern vector logo design, clean geometric emblem, centered composition, flat matte background',
    'cyberpunk': 'futuristic cyberpunk scene, wet street reflections, atmospheric fog, cinematic detail',
    'digital_art': 'masterpiece digital concept art, painterly brush strokes, intricate details, artstation featured',
    'portrait': 'studio portrait photography, Rembrandt lighting, shallow depth of field, 85mm lens, sharp eyes',
    'architecture': 'modern architectural photography, golden hour sunlight, ultra crisp lines, magazine editorial',
    'watercolor': 'delicate fine-art watercolor illustration on textured cotton paper, harmonious color wash',
  };

  /// Describes which provider + model will be used in `auto_key` mode.
  static String describeActiveKeyRoute(AiSettingsState? aiSettings, {bool isAr = true}) {
    if (aiSettings == null) {
      return isAr ? 'Nimo Flux Pro (مجاني)' : 'Nimo Flux Pro (Free)';
    }
    final activeId = aiSettings.activeProviderId;
    final activeKey = aiSettings.credentialFor(activeId).apiKey.trim();
    final activePreset = AiProviderCatalog.byId(activeId);
    final customImgModel = aiSettings.customImageModel.trim();

    if (activeKey.isNotEmpty && activePreset.supportsImageGen) {
      final m = customImgModel.isNotEmpty ? customImgModel : activePreset.defaultImageModel;
      return '${activePreset.shortName} • $m';
    }

    for (final pid in ['gemini', 'openai', 'xai', 'huggingface', 'openrouter', 'custom']) {
      final k = aiSettings.credentialFor(pid).apiKey.trim();
      if (k.isNotEmpty) {
        final p = AiProviderCatalog.byId(pid);
        final m = customImgModel.isNotEmpty ? customImgModel : p.defaultImageModel;
        return '${p.shortName} • $m';
      }
    }
    return isAr ? 'Nimo Flux Pro (مجاني)' : 'Nimo Flux Pro (Free)';
  }

  /// Generates an AI image using the upgraded multi-engine pipeline with auto-translation & smart fallback.
  Future<ImageGenResult> generateImage({
    required String prompt,
    required String styleKey,
    required String engine,
    int width = 1024,
    int height = 1024,
    String negativePrompt = '',
    bool autoEnhanceArabic = true,
    AiSettingsState? aiSettings,
    UniversalAiService? aiService,
    String? modelOverride,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      return const ImageGenResult(success: false, error: 'Prompt is empty');
    }

    // Step 1: Auto-translate & enrich Arabic prompts into vivid English for dramatically higher quality!
    String workingPrompt = cleanPrompt;
    if (autoEnhanceArabic &&
        NativeBridgeService.containsArabic(cleanPrompt) &&
        aiSettings != null &&
        aiService != null) {
      try {
        final tr = await aiService.sendChat(
          settings: aiSettings,
          systemPromptOverride:
              'Translate and enrich this Arabic image idea into ONE crisp English image generation prompt (max 40 words). Output ONLY the English prompt with no quotes or explanation.',
          messages: [AiChatMessage(role: 'user', content: cleanPrompt, timestamp: DateTime.now())],
        );
        if (tr.success && tr.text.trim().length > 4) {
          workingPrompt = tr.text.trim().replaceAll('"', '');
        }
      } catch (_) {}
    }

    final styleBoost = styleSuffixes[styleKey] ?? styleSuffixes['realistic']!;
    final negPart = negativePrompt.trim().isNotEmpty ? ', avoid: ${negativePrompt.trim()}' : '';
    final finalPrompt = '$workingPrompt, $styleBoost$negPart';
    final rawOverride = (modelOverride ?? aiSettings?.customImageModel ?? '').trim();
    final override = AiProviderCatalog.isLegacyInvalidModel(rawOverride) ? '' : rawOverride;

    try {
      // 1. AUTO MODE: Strictly tries user's configured key engine first, then gracefully falls back if enabled
      if (engine == 'auto_key' && aiSettings != null) {
        final targetProvider = _resolveProviderForAutoKey(aiSettings);
        if (targetProvider != 'pollinations') {
          try {
            return await _dispatchKeyProvider(
              providerId: targetProvider,
              finalPrompt: finalPrompt,
              displayPrompt: cleanPrompt,
              enhancedPrompt: workingPrompt,
              styleKey: styleKey,
              width: width,
              height: height,
              aiSettings: aiSettings,
              overrideModel: override,
            );
          } catch (keyErr) {
            if (aiSettings.smartFallbackEnabled) {
              final fb = await _generatePollinationsPro(
                prompt: finalPrompt,
                displayPrompt: cleanPrompt,
                enhancedPrompt: workingPrompt,
                styleKey: styleKey,
                model: _pollinationsModelForStyle(styleKey),
                width: width,
                height: height,
                usedFallback: true,
              );
              if (fb.success) return fb;
            }
            rethrow;
          }
        }
      }

      // 2. Explicit Key-Based Engines
      if (engine == 'gemini_key') {
        if (aiSettings == null || aiSettings.credentialFor('gemini').apiKey.trim().isEmpty) {
          return const ImageGenResult(
            success: false,
            error: 'يرجى إضافة مفتاح Google Gemini في الإعدادات لاستخدام توليد صور Gemini.',
          );
        }
        return await _dispatchKeyProvider(
          providerId: 'gemini',
          finalPrompt: finalPrompt,
          displayPrompt: cleanPrompt,
          enhancedPrompt: workingPrompt,
          styleKey: styleKey,
          width: width,
          height: height,
          aiSettings: aiSettings,
          overrideModel: override,
        );
      }

      if (engine == 'openai_key' || engine == 'openai_dalle3') {
        if (aiSettings == null || aiSettings.credentialFor('openai').apiKey.trim().isEmpty) {
          return const ImageGenResult(
            success: false,
            error: 'يرجى إضافة مفتاح OpenAI في الإعدادات أو اختيار الوضع التلقائي/المجاني.',
          );
        }
        return await _dispatchKeyProvider(
          providerId: 'openai',
          finalPrompt: finalPrompt,
          displayPrompt: cleanPrompt,
          enhancedPrompt: workingPrompt,
          styleKey: styleKey,
          width: width,
          height: height,
          aiSettings: aiSettings,
          overrideModel: override,
        );
      }

      if (engine == 'xai_key') {
        if (aiSettings == null || aiSettings.credentialFor('xai').apiKey.trim().isEmpty) {
          return const ImageGenResult(
            success: false,
            error: 'يرجى إضافة مفتاح xAI Grok في الإعدادات أولاً.',
          );
        }
        return await _dispatchKeyProvider(
          providerId: 'xai',
          finalPrompt: finalPrompt,
          displayPrompt: cleanPrompt,
          enhancedPrompt: workingPrompt,
          styleKey: styleKey,
          width: width,
          height: height,
          aiSettings: aiSettings,
          overrideModel: override,
        );
      }

      if (engine == 'hf_flux') {
        if (aiSettings == null || aiSettings.credentialFor('huggingface').apiKey.trim().isEmpty) {
          return const ImageGenResult(
            success: false,
            error: 'يرجى إضافة مفتاح HuggingFace في الإعدادات أو اختيار الوضع المجاني.',
          );
        }
        return await _dispatchKeyProvider(
          providerId: 'huggingface',
          finalPrompt: finalPrompt,
          displayPrompt: cleanPrompt,
          enhancedPrompt: workingPrompt,
          styleKey: styleKey,
          width: width,
          height: height,
          aiSettings: aiSettings,
          overrideModel: override,
        );
      }

      // 3. Free Pollinations Pro Multi-Model Engine
      String pModel = 'flux';
      if (engine == 'pollinations_turbo') {
        pModel = 'turbo';
      } else if (engine == 'pollinations_realism') {
        pModel = 'flux-realism';
      } else if (engine == 'pollinations_anime') {
        pModel = 'flux-anime';
      } else if (engine == 'pollinations_3d') {
        pModel = 'flux-3d';
      } else {
        pModel = _pollinationsModelForStyle(styleKey);
      }

      return await _generatePollinationsPro(
        prompt: finalPrompt,
        displayPrompt: cleanPrompt,
        enhancedPrompt: workingPrompt,
        styleKey: styleKey,
        model: pModel,
        width: width,
        height: height,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final detail = e.response?.data?.toString() ?? e.message ?? 'Network error';
      return ImageGenResult(
        success: false,
        error: code != null ? 'HTTP $code: $detail' : detail,
      );
    } catch (e) {
      return ImageGenResult(success: false, error: e.toString());
    }
  }

  String _pollinationsModelForStyle(String styleKey) {
    switch (styleKey) {
      case 'realistic':
      case 'portrait':
      case 'architecture':
        return 'flux-realism';
      case 'anime':
        return 'flux-anime';
      case '3d':
        return 'flux-3d';
      default:
        return 'flux';
    }
  }

  Future<ImageGenResult> _dispatchKeyProvider({
    required String providerId,
    required String finalPrompt,
    required String displayPrompt,
    required String enhancedPrompt,
    required String styleKey,
    required int width,
    required int height,
    required AiSettingsState aiSettings,
    required String overrideModel,
  }) async {
    final cred = aiSettings.credentialFor(providerId);
    if (providerId == 'gemini') {
      final model = overrideModel.isNotEmpty
          ? overrideModel
          : (_looksLikeGeminiImageModel(cred.model)
              ? cred.model
              : 'gemini-2.0-flash-exp-image-generation');
      return _generateGemini(
        prompt: finalPrompt,
        displayPrompt: displayPrompt,
        enhancedPrompt: enhancedPrompt,
        styleKey: styleKey,
        apiKey: cred.apiKey.trim(),
        baseUrl: cred.baseUrl.trim(),
        model: model,
      );
    }
    if (providerId == 'openai') {
      final model = overrideModel.isNotEmpty
          ? overrideModel
          : (_looksLikeOpenAiImageModel(cred.model) ? cred.model : 'gpt-image-1');
      return _generateOpenAiWithFallback(
        prompt: finalPrompt,
        displayPrompt: displayPrompt,
        enhancedPrompt: enhancedPrompt,
        styleKey: styleKey,
        apiKey: cred.apiKey.trim(),
        baseUrl: cred.baseUrl.trim().isEmpty ? 'https://api.openai.com/v1' : cred.baseUrl.trim(),
        preferredModel: model,
        providerLabel: 'OpenAI',
        width: width,
        height: height,
      );
    }
    if (providerId == 'xai') {
      return _generateOpenAiWithFallback(
        prompt: finalPrompt,
        displayPrompt: displayPrompt,
        enhancedPrompt: enhancedPrompt,
        styleKey: styleKey,
        apiKey: cred.apiKey.trim(),
        baseUrl: cred.baseUrl.trim().isEmpty ? 'https://api.x.ai/v1' : cred.baseUrl.trim(),
        preferredModel: overrideModel.isNotEmpty ? overrideModel : 'grok-2-image',
        providerLabel: 'xAI Grok',
        width: width,
        height: height,
      );
    }
    if (providerId == 'huggingface') {
      return _generateHuggingFace(
        finalPrompt,
        displayPrompt,
        enhancedPrompt,
        styleKey,
        cred.apiKey.trim(),
        overrideModel.isNotEmpty ? overrideModel : 'black-forest-labs/FLUX.1-schnell',
      );
    }
    return _generateOpenAiWithFallback(
      prompt: finalPrompt,
      displayPrompt: displayPrompt,
      enhancedPrompt: enhancedPrompt,
      styleKey: styleKey,
      apiKey: cred.apiKey.trim(),
      baseUrl: cred.baseUrl.trim(),
      preferredModel: overrideModel.isNotEmpty ? overrideModel : 'dall-e-3',
      providerLabel: 'Custom API',
      width: width,
      height: height,
    );
  }

  Future<ImageGenResult> _generatePollinationsPro({
    required String prompt,
    required String displayPrompt,
    required String enhancedPrompt,
    required String styleKey,
    required String model,
    required int width,
    required int height,
    bool usedFallback = false,
  }) async {
    final modelsToTry = <String>[model, if (model != 'flux') 'flux', if (model != 'turbo') 'turbo'];
    Object? lastErr;

    for (final m in modelsToTry) {
      try {
        final seed = Random().nextInt(9999999);
        final encoded = Uri.encodeComponent(prompt);
        final url =
            'https://image.pollinations.ai/prompt/$encoded?width=$width&height=$height&model=$m&seed=$seed&nologo=true&enhance=true';

        final res = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = Uint8List.fromList(res.data ?? const <int>[]);
        if (bytes.length < 1000) {
          throw Exception('Image server returned invalid bytes.');
        }

        final id = 'img_${DateTime.now().millisecondsSinceEpoch}';
        final localPath = await _cacheBytesToDisk(id, bytes);
        final item = GeneratedImageItem(
          id: id,
          prompt: displayPrompt,
          enhancedPrompt: enhancedPrompt,
          style: styleKey,
          engine: 'Nimo Pro • $m${usedFallback ? ' (Auto)' : ''}',
          imageUrl: url,
          localPath: localPath,
          createdAt: DateTime.now(),
        );
        await saveToHistory(item);
        return ImageGenResult(success: true, item: item, bytes: bytes, usedFallback: usedFallback);
      } catch (e) {
        lastErr = e;
      }
    }
    return ImageGenResult(success: false, error: 'Image generation failed: $lastErr');
  }

  String _resolveProviderForAutoKey(AiSettingsState ai) {
    final activeId = ai.activeProviderId;
    final activeKey = ai.credentialFor(activeId).apiKey.trim();
    if (activeKey.isNotEmpty &&
        const {'gemini', 'openai', 'xai', 'huggingface', 'custom'}.contains(activeId)) {
      return activeId;
    }
    for (final pid in ['gemini', 'openai', 'xai', 'huggingface', 'custom']) {
      if (ai.credentialFor(pid).apiKey.trim().isNotEmpty) return pid;
    }
    return 'pollinations';
  }

  bool _looksLikeGeminiImageModel(String m) {
    final l = m.toLowerCase();
    return l.contains('image') || l.contains('imagen');
  }

  bool _looksLikeOpenAiImageModel(String m) {
    final l = m.toLowerCase();
    return l.contains('image') || l.contains('dall-e');
  }

  /// Google Gemini Native Image Generation (Gemini 2.0/2.5 Image + Imagen 3 fallback).
  Future<ImageGenResult> _generateGemini({
    required String prompt,
    required String displayPrompt,
    required String enhancedPrompt,
    required String styleKey,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final cleanBase = (baseUrl.isEmpty ? 'https://generativelanguage.googleapis.com/v1beta' : baseUrl)
        .replaceAll(RegExp(r"""/+$"""), '');

    final genContentModels = <String>[
      model,
      if (model != 'gemini-2.0-flash-exp-image-generation') 'gemini-2.0-flash-exp-image-generation',
      if (model != 'gemini-2.5-flash-image-preview') 'gemini-2.5-flash-image-preview',
    ];

    Object? lastErr;
    for (final m in genContentModels) {
      if (m.contains('imagen')) continue;
      try {
        final cleanModel = m.startsWith('models/') ? m.substring(7) : m;
        final res = await _dio.post<Map<String, dynamic>>(
          '$cleanBase/models/$cleanModel:generateContent',
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
          ),
          data: {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': 'Generate a high quality image of: $prompt'}
                ],
              }
            ],
            'generationConfig': {
              'responseModalities': ['TEXT', 'IMAGE'],
            },
          },
        );
        final candidates = res.data?['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = ((candidates.first as Map<String, dynamic>)['content']
              as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final p in parts) {
              if (p is Map<String, dynamic>) {
                final inlineData = (p['inlineData'] ?? p['inline_data']) as Map<String, dynamic>?;
                final b64 = inlineData?['data']?.toString() ?? '';
                if (b64.isNotEmpty) {
                  final bytes = base64Decode(b64);
                  final id = 'gem_${DateTime.now().millisecondsSinceEpoch}';
                  final localPath = await _cacheBytesToDisk(id, bytes);
                  final item = GeneratedImageItem(
                    id: id,
                    prompt: displayPrompt,
                    enhancedPrompt: enhancedPrompt,
                    style: styleKey,
                    engine: 'Gemini • $cleanModel',
                    imageUrl: '',
                    localPath: localPath,
                    base64Bytes: b64,
                    createdAt: DateTime.now(),
                  );
                  await saveToHistory(item);
                  return ImageGenResult(success: true, item: item, bytes: bytes);
                }
              }
            }
          }
        }
      } catch (e) {
        lastErr = e;
      }
    }

    // Try Google Imagen 3 `:predict` endpoint as backup
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$cleanBase/models/imagen-3.0-generate-002:predict',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
        ),
        data: {
          'instances': [
            {'prompt': prompt}
          ],
          'parameters': {'sampleCount': 1},
        },
      );
      final preds = res.data?['predictions'] as List<dynamic>?;
      if (preds != null && preds.isNotEmpty) {
        final b64 = (preds.first as Map<String, dynamic>)['bytesBase64Encoded']?.toString() ?? '';
        if (b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          final id = 'imgn_${DateTime.now().millisecondsSinceEpoch}';
          final localPath = await _cacheBytesToDisk(id, bytes);
          final item = GeneratedImageItem(
            id: id,
            prompt: displayPrompt,
            enhancedPrompt: enhancedPrompt,
            style: styleKey,
            engine: 'Google Imagen 3',
            imageUrl: '',
            localPath: localPath,
            base64Bytes: b64,
            createdAt: DateTime.now(),
          );
          await saveToHistory(item);
          return ImageGenResult(success: true, item: item, bytes: bytes);
        }
      }
    } catch (e) {
      lastErr = e;
    }

    throw Exception('Gemini Image Generation failed: $lastErr');
  }

  /// OpenAI / xAI / Custom OpenAI-Compatible `/images/generations` with real model fallback.
  Future<ImageGenResult> _generateOpenAiWithFallback({
    required String prompt,
    required String displayPrompt,
    required String enhancedPrompt,
    required String styleKey,
    required String apiKey,
    required String baseUrl,
    required String preferredModel,
    required String providerLabel,
    required int width,
    required int height,
  }) async {
    final cleanBase = baseUrl.replaceAll(RegExp(r"""/+$"""), '');
    final endpoint = cleanBase.endsWith('/images/generations')
        ? cleanBase
        : '$cleanBase/images/generations';

    final modelsToTry = providerLabel == 'OpenAI'
        ? <String>[
            preferredModel,
            if (preferredModel != 'gpt-image-1') 'gpt-image-1',
            if (preferredModel != 'dall-e-3') 'dall-e-3',
          ]
        : <String>[preferredModel];

    Object? lastErr;
    for (final model in modelsToTry) {
      try {
        final sizeStr = model == 'dall-e-3'
            ? (width > height ? '1792x1024' : (height > width ? '1024x1792' : '1024x1024'))
            : (width > height ? '1536x1024' : (height > width ? '1024x1536' : '1024x1024'));

        final res = await _dio.post<Map<String, dynamic>>(
          endpoint,
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
          data: {
            'model': model,
            'prompt': prompt,
            'n': 1,
            if (providerLabel == 'OpenAI') 'size': sizeStr,
            if (model == 'dall-e-3') 'quality': 'hd',
          },
        );

        final dataList = res.data?['data'] as List<dynamic>?;
        final first = dataList?.first as Map<String, dynamic>?;
        final b64 = first?['b64_json']?.toString() ?? '';
        final url = first?['url']?.toString() ?? '';

        Uint8List bytes;
        if (b64.isNotEmpty) {
          bytes = base64Decode(b64);
        } else if (url.isNotEmpty) {
          final imgRes = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
          bytes = Uint8List.fromList(imgRes.data ?? const <int>[]);
        } else {
          throw Exception('No image returned by $providerLabel ($model)');
        }

        final id = 'oai_${DateTime.now().millisecondsSinceEpoch}';
        final localPath = await _cacheBytesToDisk(id, bytes);
        final item = GeneratedImageItem(
          id: id,
          prompt: displayPrompt,
          enhancedPrompt: enhancedPrompt,
          style: styleKey,
          engine: '$providerLabel • $model',
          imageUrl: url,
          localPath: localPath,
          base64Bytes: b64.isNotEmpty ? b64 : null,
          createdAt: DateTime.now(),
        );
        await saveToHistory(item);
        return ImageGenResult(success: true, item: item, bytes: bytes);
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('$providerLabel image generation failed: $lastErr');
  }

  /// HuggingFace Inference Router (`router.huggingface.co/hf-inference/models/...`).
  Future<ImageGenResult> _generateHuggingFace(
    String prompt,
    String displayPrompt,
    String enhancedPrompt,
    String styleKey,
    String token,
    String model,
  ) async {
    final modelsToTry = <String>[
      model,
      if (model != 'black-forest-labs/FLUX.1-schnell') 'black-forest-labs/FLUX.1-schnell',
      'stabilityai/stable-diffusion-xl-base-1.0',
    ];
    Object? lastErr;
    for (final m in modelsToTry) {
      try {
        final res = await _dio.post<List<int>>(
          'https://router.huggingface.co/hf-inference/models/$m',
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          ),
          data: {'inputs': prompt},
        );
        final bytes = Uint8List.fromList(res.data ?? const <int>[]);
        if (bytes.length < 1000) throw Exception('Invalid HuggingFace image data.');

        final id = 'hf_${DateTime.now().millisecondsSinceEpoch}';
        final localPath = await _cacheBytesToDisk(id, bytes);
        final item = GeneratedImageItem(
          id: id,
          prompt: displayPrompt,
          enhancedPrompt: enhancedPrompt,
          style: styleKey,
          engine: 'HuggingFace • ${m.split('/').last}',
          imageUrl: '',
          localPath: localPath,
          base64Bytes: base64Encode(bytes),
          createdAt: DateTime.now(),
        );
        await saveToHistory(item);
        return ImageGenResult(success: true, item: item, bytes: bytes);
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('HuggingFace failed: $lastErr');
  }

  Future<String?> _cacheBytesToDisk(String id, Uint8List bytes) async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/nimo_images');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$id.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<List<GeneratedImageItem>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHistoryKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(GeneratedImageItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveToHistory(GeneratedImageItem item) async {
    try {
      final existing = await loadHistory();
      final updated = [item, ...existing];
      final trimmed = updated.length > 30 ? updated.sublist(0, 30) : updated;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHistoryKey, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kHistoryKey);
    } catch (_) {}
  }
}

final imageGenServiceProvider = Provider<ImageGenService>((ref) => ImageGenService());

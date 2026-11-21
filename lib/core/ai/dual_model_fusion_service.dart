import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/ai/universal_ai_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Result of running TWO AI models together in Dual-Model Fusion mode.
class DualFusionResult {
  final bool success;
  final String mergedText;
  final String? error;
  final AiResponseResult? resultA;
  final AiResponseResult? resultB;
  final String mode; // 'synergy' or 'refine'
  final int totalLatencyMs;
  final String fusionBadge;

  const DualFusionResult({
    required this.success,
    required this.mergedText,
    this.error,
    this.resultA,
    this.resultB,
    required this.mode,
    required this.totalLatencyMs,
    required this.fusionBadge,
  });
}

/// Nimo v9.0 OmniControl — Dual-Model Fusion Engine.
/// Combines TWO AI models/providers to work together on a single prompt:
/// 1. `synergy`: Model A + Model B answer in parallel, then a synthesis pass merges the
///    strongest facts, logic & clarity from both into one super-answer.
/// 2. `refine`: Model A produces the initial deep draft, then Model B reviews, verifies,
///    fixes any edge-cases, and produces the final perfected answer.
class DualModelFusionService {
  final UniversalAiService aiService;

  const DualModelFusionService(this.aiService);

  Future<DualFusionResult> runDualFusion({
    required AiSettingsState settings,
    required List<AiChatMessage> messages,
    required String providerA,
    required String providerB,
    required String mode, // 'synergy' | 'refine'
    String? systemPromptOverride,
    String? ragContext,
    void Function(String statusText)? onStatus,
    bool isArabic = true,
  }) async {
    final sw = Stopwatch()..start();
    final presetA = AiProviderCatalog.byId(providerA);
    final presetB = AiProviderCatalog.byId(providerB);

    if (mode == 'refine') {
      // Pipeline Mode: Model A drafts -> Model B critiques & upgrades
      onStatus?.call(
        isArabic
            ? 'المرحلة 1/2: ${presetA.shortName} يكتب المسودة الأولى...'
            : 'Stage 1/2: ${presetA.shortName} drafting initial answer...',
      );
      final draftRes = await aiService.sendChat(
        settings: settings,
        messages: messages,
        systemPromptOverride: systemPromptOverride,
        ragContext: ragContext,
        providerIdOverride: providerA,
        allowFallback: true,
      );

      if (!draftRes.success) {
        // Fallback directly to Model B
        final fb = await aiService.sendChat(
          settings: settings,
          messages: messages,
          systemPromptOverride: systemPromptOverride,
          ragContext: ragContext,
          providerIdOverride: providerB,
          allowFallback: true,
        );
        sw.stop();
        return DualFusionResult(
          success: fb.success,
          mergedText: fb.text,
          error: fb.error,
          resultA: draftRes,
          resultB: fb,
          mode: mode,
          totalLatencyMs: sw.elapsedMilliseconds,
          fusionBadge: '${presetB.shortName} (Fallback)',
        );
      }

      onStatus?.call(
        isArabic
            ? 'المرحلة 2/2: ${presetB.shortName} يراجع ويطوّر الإجابة...'
            : 'Stage 2/2: ${presetB.shortName} reviewing & refining...',
      );
      final lastUserPrompt = messages.lastWhere(
        (m) => m.role == 'user',
        orElse: () => messages.last,
      ).content;

      final refinePrompt = '''
User Question:
$lastUserPrompt

Initial Answer from ${draftRes.providerName} (${draftRes.modelName}):
${draftRes.text}

Your Role (Dual-Model Refiner):
Review the initial answer critically. Fix any inaccuracies, fill in missing practical details, sharpen clarity, and output ONE complete, superior final response in the same language as the user's question. Do not mention "Model A" or meta commentary — just deliver the perfected answer.
''';

      final refinedRes = await aiService.sendChat(
        settings: settings,
        messages: [AiChatMessage(role: 'user', content: refinePrompt, timestamp: DateTime.now())],
        systemPromptOverride: systemPromptOverride,
        providerIdOverride: providerB,
        allowFallback: false,
      );

      sw.stop();
      if (refinedRes.success && refinedRes.text.trim().isNotEmpty) {
        return DualFusionResult(
          success: true,
          mergedText: refinedRes.text.trim(),
          resultA: draftRes,
          resultB: refinedRes,
          mode: mode,
          totalLatencyMs: sw.elapsedMilliseconds,
          fusionBadge: '${presetA.shortName} → ${presetB.shortName}',
        );
      }

      return DualFusionResult(
        success: true,
        mergedText: draftRes.text.trim(),
        resultA: draftRes,
        resultB: refinedRes,
        mode: mode,
        totalLatencyMs: sw.elapsedMilliseconds,
        fusionBadge: '${presetA.shortName} (Solo)',
      );
    }

    // Synergy Merge Mode: Run A & B in parallel, then synthesize!
    onStatus?.call(
      isArabic
          ? 'جاري تشغيل ${presetA.shortName} + ${presetB.shortName} بالتوازي...'
          : 'Running ${presetA.shortName} + ${presetB.shortName} in parallel...',
    );

    final parallel = await Future.wait([
      aiService.sendChat(
        settings: settings,
        messages: messages,
        systemPromptOverride: systemPromptOverride,
        ragContext: ragContext,
        providerIdOverride: providerA,
        allowFallback: false,
      ),
      aiService.sendChat(
        settings: settings,
        messages: messages,
        systemPromptOverride: systemPromptOverride,
        ragContext: ragContext,
        providerIdOverride: providerB,
        allowFallback: false,
      ),
    ]);

    final resA = parallel[0];
    final resB = parallel[1];

    if (!resA.success && !resB.success) {
      sw.stop();
      return DualFusionResult(
        success: false,
        mergedText: '',
        error: resA.error ?? resB.error ?? 'Both models failed.',
        resultA: resA,
        resultB: resB,
        mode: mode,
        totalLatencyMs: sw.elapsedMilliseconds,
        fusionBadge: '${presetA.shortName} + ${presetB.shortName}',
      );
    }

    if (resA.success && !resB.success) {
      sw.stop();
      return DualFusionResult(
        success: true,
        mergedText: resA.text.trim(),
        resultA: resA,
        resultB: resB,
        mode: mode,
        totalLatencyMs: sw.elapsedMilliseconds,
        fusionBadge: '${presetA.shortName} (Partner offline)',
      );
    }

    if (!resA.success && resB.success) {
      sw.stop();
      return DualFusionResult(
        success: true,
        mergedText: resB.text.trim(),
        resultA: resA,
        resultB: resB,
        mode: mode,
        totalLatencyMs: sw.elapsedMilliseconds,
        fusionBadge: '${presetB.shortName} (Primary offline)',
      );
    }

    // Both succeeded -> Synthesize into ONE unified super-answer!
    onStatus?.call(
      isArabic
          ? 'جاري دمج أقوى أفكار النموذجين في إجابة واحدة خارقة...'
          : 'Synthesizing the best insights from both models...',
    );

    final lastUserPrompt = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => messages.last,
    ).content;

    final fused = await fuseTwoResponses(
      settings: settings,
      originalPrompt: lastUserPrompt,
      answerA: resA.text,
      labelA: '${resA.providerName} (${resA.modelName})',
      answerB: resB.text,
      labelB: '${resB.providerName} (${resB.modelName})',
      synthesizerProviderId: providerA,
    );

    sw.stop();
    if (fused.success && fused.text.trim().isNotEmpty) {
      return DualFusionResult(
        success: true,
        mergedText: fused.text.trim(),
        resultA: resA,
        resultB: resB,
        mode: mode,
        totalLatencyMs: sw.elapsedMilliseconds,
        fusionBadge: '${presetA.shortName} + ${presetB.shortName} Fusion',
      );
    }

    // Graceful fallback if synthesis call fails: return clean combined sections
    final combined = isArabic
        ? '### خلاصة ${presetA.shortName}\n${resA.text.trim()}\n\n### إضافة ${presetB.shortName}\n${resB.text.trim()}'
        : '### ${presetA.shortName}\n${resA.text.trim()}\n\n### ${presetB.shortName}\n${resB.text.trim()}';
    return DualFusionResult(
      success: true,
      mergedText: combined,
      resultA: resA,
      resultB: resB,
      mode: mode,
      totalLatencyMs: sw.elapsedMilliseconds,
      fusionBadge: '${presetA.shortName} + ${presetB.shortName}',
    );
  }

  /// Synthesizes two already-generated answers (used by both Dual-Model Chat & AI Battle Arena).
  Future<AiResponseResult> fuseTwoResponses({
    required AiSettingsState settings,
    required String originalPrompt,
    required String answerA,
    required String labelA,
    required String answerB,
    required String labelB,
    String? synthesizerProviderId,
  }) async {
    final synthPrompt = '''
Original User Request:
$originalPrompt

--- Response from Model 1 ($labelA) ---
$answerA

--- Response from Model 2 ($labelB) ---
$answerB

Task:
Combine the strongest facts, clearest explanations, and best code/steps from BOTH responses into ONE cohesive, accurate, well-structured super-answer in the user's language. Eliminate redundancy and resolve any contradiction using the more accurate fact. Output only the final merged answer.
''';
    return aiService.sendChat(
      settings: settings,
      messages: [AiChatMessage(role: 'user', content: synthPrompt, timestamp: DateTime.now())],
      systemPromptOverride:
          'You are Nimo v9.0 Dual-Model Fusion Synthesizer. Merge two AI answers into one superior, unified response.',
      providerIdOverride: synthesizerProviderId ?? settings.activeProviderId,
      allowFallback: true,
    );
  }
}

final dualModelFusionProvider = Provider<DualModelFusionService>(
  (ref) => DualModelFusionService(ref.watch(universalAiServiceProvider)),
);

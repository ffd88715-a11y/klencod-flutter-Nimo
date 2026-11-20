import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

/// Nimo v6.0 Titan — Foolproof Smart API Key Control Center.
/// Auto-detects the provider on EVERY paste, type, save, or test — impossible to bind to the wrong provider!
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _devName = 'YOSSEF JOO';
  static const String _devWhatsApp = '01029892573';

  late String _selectedProviderId;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _systemPromptCtrl;

  bool _obscureKey = true;
  bool _isTesting = false;
  bool _isDiscovering = false;
  bool _showKeyGuide = false;
  String? _discoveryStatus;
  AiResponseResult? _lastTestResult;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsProvider);
    _selectedProviderId = ai.activeProviderId;
    final cred = ai.credentialFor(_selectedProviderId);

    _apiKeyCtrl = TextEditingController(text: cred.apiKey);
    _modelCtrl = TextEditingController(text: cred.model);
    _baseUrlCtrl = TextEditingController(text: cred.baseUrl);
    _systemPromptCtrl = TextEditingController(text: ai.customSystemPrompt);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  void _switchProvider(String providerId) {
    final ai = ref.read(aiSettingsProvider);
    final cred = ai.credentialFor(providerId);
    setState(() {
      _selectedProviderId = providerId;
      _apiKeyCtrl.text = cred.apiKey;
      _modelCtrl.text = cred.model;
      _baseUrlCtrl.text = cred.baseUrl;
      _lastTestResult = null;
      _discoveryStatus = null;
    });
    ref.read(aiSettingsProvider.notifier).selectProvider(providerId);
  }

  /// Auto-switches provider whenever the pasted/typed key prefix clearly matches a real provider.
  void _syncProviderFromKeyPrefix(String rawKey) {
    final key = rawKey.trim();
    if (key.isEmpty || _selectedProviderId == 'custom') return;
    final detected = AiProviderCatalog.detectProviderFromKey(key);
    if (detected == null) return;
    // Allow user to keep DeepSeek if they explicitly selected DeepSeek for an `sk-...` key
    if (detected == 'openai' && _selectedProviderId == 'deepseek') return;
    if (detected != _selectedProviderId) {
      final preset = AiProviderCatalog.byId(detected);
      setState(() {
        _selectedProviderId = detected;
        _baseUrlCtrl.text = preset.defaultBaseUrl;
        _modelCtrl.text = preset.defaultModel;
      });
    }
  }

  /// Auto-detects provider from key prefix, discovers the latest live model, saves & verifies live connection!
  Future<void> _autoBindLatestModel({String? pastedKeyOverride}) async {
    final key = (pastedKeyOverride ?? _apiKeyCtrl.text).trim();
    if (key.isNotEmpty) {
      _syncProviderFromKeyPrefix(key);
    }
    final preset = AiProviderCatalog.byId(_selectedProviderId);
    if (key.isEmpty && preset.requiresApiKey) {
      final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAr ? 'الصق مفتاح API أولاً ثم اضغط الربط التلقائي.' : 'Paste an API key first.')),
      );
      return;
    }
    NimoSoundFx.click();

    final baseUrl = _baseUrlCtrl.text.trim().isEmpty ? preset.defaultBaseUrl : _baseUrlCtrl.text.trim();

    setState(() {
      _isDiscovering = true;
      _discoveryStatus = null;
      _lastTestResult = null;
    });

    final service = ref.read(universalAiServiceProvider);
    final discovery = await service.discoverLatestModel(
      providerId: _selectedProviderId,
      apiKey: key,
      baseUrl: baseUrl,
    );

    final chosenModel = discovery.latestModel.isNotEmpty ? discovery.latestModel : preset.defaultModel;
    await ref.read(aiSettingsProvider.notifier).saveProviderConfig(
          providerId: _selectedProviderId,
          apiKey: key,
          model: chosenModel,
          baseUrl: baseUrl,
          discoveredModels: discovery.availableModels,
        );

    final settings = ref.read(aiSettingsProvider);
    final ping = await service.testConnection(settings, providerIdOverride: _selectedProviderId);

    // If self-heal succeeded with an alternate working model, save THAT exact verified model!
    final verifiedModel = (ping.success && ping.modelName.isNotEmpty) ? ping.modelName : chosenModel;
    if (verifiedModel != chosenModel) {
      await ref.read(aiSettingsProvider.notifier).saveProviderConfig(
            providerId: _selectedProviderId,
            apiKey: key,
            model: verifiedModel,
            baseUrl: baseUrl,
            discoveredModels: discovery.availableModels,
          );
    }

    if (!mounted) return;
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    setState(() {
      _isDiscovering = false;
      _modelCtrl.text = verifiedModel;
      _lastTestResult = ping;
      _discoveryStatus = ping.success
          ? (isAr
              ? 'تم الربط والتحقق تلقائياً مع ${preset.shortName} • $verifiedModel (${ping.latencyMs}ms)'
              : 'Verified & bound to ${preset.shortName} • $verifiedModel (${ping.latencyMs}ms)')
          : (isAr
              ? 'تم التعرف على ${preset.shortName} ($verifiedModel) — راجع رسالة التشخيص بالأسفل'
              : 'Detected ${preset.shortName} ($verifiedModel) — check diagnostic below');
    });
  }

  Future<void> _saveCurrentProvider({bool showToast = true}) async {
    // Always auto-detect provider before saving so a real key is NEVER saved under `pollinations`!
    _syncProviderFromKeyPrefix(_apiKeyCtrl.text);
    final preset = AiProviderCatalog.byId(_selectedProviderId);
    final cleanModel = _modelCtrl.text.trim();
    final safeModel = (cleanModel.isEmpty || AiProviderCatalog.isLegacyInvalidModel(cleanModel))
        ? preset.defaultModel
        : cleanModel;

    await ref.read(aiSettingsProvider.notifier).saveProviderConfig(
          providerId: _selectedProviderId,
          apiKey: _apiKeyCtrl.text,
          model: safeModel,
          baseUrl: _baseUrlCtrl.text.trim().isEmpty ? preset.defaultBaseUrl : _baseUrlCtrl.text.trim(),
        );
    await ref.read(aiSettingsProvider.notifier).updateAdvanced(
          customSystemPrompt: _systemPromptCtrl.text.trim(),
        );
    if (showToast && mounted) {
      final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            isAr ? 'تم حفظ وتفعيل ${preset.name} ($safeModel) بنجاح!' : '${preset.name} ($safeModel) saved!',
          ),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    await _saveCurrentProvider(showToast: false);
    setState(() {
      _isTesting = true;
      _lastTestResult = null;
    });
    final settings = ref.read(aiSettingsProvider);
    final service = ref.read(universalAiServiceProvider);
    final result = await service.testConnection(settings, providerIdOverride: _selectedProviderId);
    if (!mounted) return;
    if (result.success && result.modelName.isNotEmpty) {
      _modelCtrl.text = result.modelName;
      await ref.read(aiSettingsProvider.notifier).saveProviderConfig(
            providerId: _selectedProviderId,
            apiKey: _apiKeyCtrl.text,
            model: result.modelName,
            baseUrl: _baseUrlCtrl.text,
          );
    }
    setState(() {
      _isTesting = false;
      _lastTestResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learnerProfileProvider);
    final ai = ref.watch(aiSettingsProvider);
    final bridge = ref.read(nativeBridgeProvider);
    final isAr = profile.uiLocale == 'ar';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final preset = AiProviderCatalog.byId(_selectedProviderId);
    final cred = ai.credentialFor(_selectedProviderId);
    final modelChoices = <String>{
      ...cred.discoveredModels,
      ...preset.suggestedModels,
    }.take(12).toList();
    final guideSteps = isAr ? preset.keyGuideAr : preset.keyGuideEn;
    final voiceStatus = RealisticTtsService.describeActiveVoiceEngine(ai, isAr: isAr);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'الإعدادات ومفاتيح AI الذكية' : 'Settings & Smart AI Keys'),
        actions: [
          TextButton(
            onPressed: _saveCurrentProvider,
            child: Text(
              isAr ? 'حفظ' : 'Save',
              style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          // Active AI Engine + Voice Engine Status Hero
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                IosIconBadge(icon: ai.activePreset.icon, color: ai.activePreset.badgeColor, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isAr ? 'المحرك النشط حالياً' : 'Active AI Engine', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        '${ai.activePreset.shortName} • ${ai.activeModel}',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          IosStatusPill(
                            label: ai.isConfigured
                                ? (isAr ? 'متصل وجاهز' : 'Ready')
                                : (isAr ? 'بانتظار المفتاح' : 'Key Needed'),
                            color: ai.isConfigured ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                          ),
                          IosStatusPill(
                            label: voiceStatus,
                            color: TalkoraColors.iosTeal,
                            icon: CupertinoIcons.waveform,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Provider Selector (12 Engines)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
            child: Text(
              (isAr ? 'اختر مزود الذكاء أو الصق أي مفتاح وسيتعرف عليه تلقائياً' : 'SELECT PROVIDER OR PASTE ANY KEY')
                  .toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? TalkoraColors.darkSecondaryText : TalkoraColors.lightSecondaryText,
              ),
            ),
          ),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AiProviderCatalog.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = AiProviderCatalog.all[index];
                final isSelected = item.id == _selectedProviderId;
                final hasKey = !item.requiresApiKey ||
                    (ai.credentials[item.id]?.apiKey.trim().isNotEmpty ?? false);

                return GestureDetector(
                  onTap: () => _switchProvider(item.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 106,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
                          : (isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark ? TalkoraColors.darkSeparator : TalkoraColors.lightSeparator)
                                .withValues(alpha: 0.45),
                        width: isSelected ? 1.8 : 0.6,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IosIconBadge(icon: item.icon, color: item.badgeColor, size: 34),
                            if (hasKey)
                              Positioned(
                                right: -3,
                                top: -3,
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: TalkoraColors.iosGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? TalkoraColors.darkSurface : Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.shortName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : (isDark ? TalkoraColors.darkText : TalkoraColors.lightMainText),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.hasFreeTier)
                          Text(
                            isAr ? 'مجاني' : 'Free',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: TalkoraColors.iosGreen,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Smart Credentials Card
          IosGroupedSection(
            header: isAr ? 'الربط الفوري — ${preset.name}' : '${preset.name} INSTANT CONNECT',
            footer: isAr ? preset.descriptionAr : preset.descriptionEn,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isAr ? 'مفتاح API (يتعرف على المزود تلقائياً)' : 'API Key (Auto-Detects Provider)',
                            style: theme.textTheme.labelLarge),
                        Row(
                          children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              onPressed: () async {
                                final clip = await Clipboard.getData(Clipboard.kTextPlain);
                                final txt = clip?.text?.trim() ?? '';
                                if (txt.isNotEmpty) {
                                  setState(() => _apiKeyCtrl.text = txt);
                                  await _autoBindLatestModel(pastedKeyOverride: txt);
                                }
                              },
                              child: Text(
                                isAr ? 'لصق وربط فوري' : 'Paste & Connect',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                              ),
                            ),
                            if (_apiKeyCtrl.text.isNotEmpty)
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                onPressed: () {
                                  setState(() => _apiKeyCtrl.clear());
                                  ref.read(aiSettingsProvider.notifier).clearApiKey(_selectedProviderId);
                                },
                                child: Text(
                                  isAr ? 'مسح' : 'Clear',
                                  style: const TextStyle(fontSize: 13, color: TalkoraColors.iosRed),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _apiKeyCtrl,
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (val) {
                          _syncProviderFromKeyPrefix(val);
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: preset.apiKeyPlaceholder,
                          prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: TalkoraColors.iosGreen),
                        onPressed: _isDiscovering ? null : () => _autoBindLatestModel(),
                        icon: _isDiscovering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CupertinoActivityIndicator(color: Colors.white),
                              )
                            : const Icon(CupertinoIcons.sparkles, size: 18),
                        label: Text(
                          isAr ? 'اتصال تلقائي بأحدث موديل + فحص المفتاح' : 'Auto-Connect Latest Model & Verify',
                        ),
                      ),
                    ),

                    if (_discoveryStatus != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: TalkoraColors.iosBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _discoveryStatus!,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    Text(isAr ? 'النموذج النشط (Model ID)' : 'Active Model ID', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _modelCtrl,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: preset.defaultModel,
                          prefixIcon: const Icon(CupertinoIcons.cube_box, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: modelChoices.map((modelId) {
                        final selected = _modelCtrl.text.trim() == modelId;
                        return ChoiceChip(
                          label: Text(modelId, style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          selectedColor: theme.colorScheme.primary.withValues(alpha: 0.18),
                          onSelected: (_) {
                            NimoSoundFx.click();
                            setState(() => _modelCtrl.text = modelId);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isAr ? 'رابط الخادم (Base URL)' : 'API Base URL', style: theme.textTheme.labelLarge),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(() => _baseUrlCtrl.text = preset.defaultBaseUrl),
                          child: Text(isAr ? 'الافتراضي' : 'Reset', style: TextStyle(fontSize: 13, color: theme.colorScheme.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _baseUrlCtrl,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          hintText: preset.defaultBaseUrl,
                          prefixIcon: const Icon(CupertinoIcons.link, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveCurrentProvider,
                            icon: const Icon(CupertinoIcons.checkmark_alt_circle, size: 19),
                            label: Text(isAr ? 'حفظ وتفعيل' : 'Save'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator())
                                : const Icon(CupertinoIcons.antenna_radiowaves_left_right, size: 18),
                            label: Text(isAr ? 'اختبار الاتصال' : 'Test API'),
                          ),
                        ),
                      ],
                    ),
                    if (_lastTestResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_lastTestResult!.success ? TalkoraColors.iosGreen : TalkoraColors.iosRed)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _lastTestResult!.success
                                  ? (isAr
                                      ? 'متصل بنجاح مع ${_lastTestResult!.modelName} (${_lastTestResult!.latencyMs} ms)'
                                      : 'Connected to ${_lastTestResult!.modelName} (${_lastTestResult!.latencyMs} ms)')
                                  : (isAr ? 'تعذّر الاتصال — التفاصيل:' : 'Connection Failed:'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _lastTestResult!.success ? TalkoraColors.iosGreen : TalkoraColors.iosRed,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              _lastTestResult!.success
                                  ? _lastTestResult!.text
                                  : (_lastTestResult!.error == 'MISSING_API_KEY'
                                      ? (isAr ? 'يرجى إدخال مفتاح API أولاً.' : 'Please enter an API key first.')
                                      : (_lastTestResult!.error ?? 'Unknown error')),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Collapsible Key Guide
          IosGroupedSection(
            header: isAr ? 'كيفية الحصول على مفتاح ${preset.shortName}' : 'HOW TO GET ${preset.shortName.toUpperCase()} KEY',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IosStatusPill(
                          label: preset.hasFreeTier
                              ? (isAr ? 'يدعم باقة مجانية' : 'Free Tier Available')
                              : (isAr ? 'مفتاح API' : 'API Key'),
                          color: preset.hasFreeTier ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                        ),
                        TextButton(
                          onPressed: () => setState(() => _showKeyGuide = !_showKeyGuide),
                          child: Text(_showKeyGuide ? (isAr ? 'إخفاء' : 'Hide') : (isAr ? 'عرض الشرح' : 'Show Guide')),
                        ),
                      ],
                    ),
                    if (_showKeyGuide) ...[
                      const SizedBox(height: 8),
                      for (int i = 0; i < guideSteps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${i + 1}. ${guideSteps[i]}', style: theme.textTheme.bodyMedium),
                        ),
                    ],
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () => bridge.openUrl(preset.keyConsoleUrl),
                        icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 17),
                        label: Text(isAr ? 'افتح صفحة مفتاح ${preset.shortName}' : 'Open ${preset.shortName} Console'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Super Controls
          IosGroupedSection(
            header: isAr ? 'قدرات Nimo v6.0 Titan' : 'NIMO v6.0 TITAN CONTROLS',
            children: [
              IosSettingsRow(
                icon: CupertinoIcons.arrow_branch,
                iconColor: TalkoraColors.iosBlue,
                title: isAr ? 'التحويل الذكي التلقائي (Smart Fallback)' : 'Smart Auto-Fallback',
                subtitle: isAr
                    ? 'التبديل تلقائياً للمفتاح الاحتياطي أو السحابة المجانية عند تعطل أي خادم'
                    : 'Auto-switch to backup keys or Free Cloud AI if primary fails',
                trailing: CupertinoSwitch(
                  value: ai.smartFallbackEnabled,
                  activeTrackColor: TalkoraColors.iosGreen,
                  onChanged: (v) =>
                      ref.read(aiSettingsProvider.notifier).updateAdvanced(smartFallbackEnabled: v),
                ),
              ),
              IosSettingsRow(
                icon: CupertinoIcons.sparkles,
                iconColor: TalkoraColors.iosPurple,
                title: isAr ? 'وضع التفكير العميق (Deep Thinking)' : 'Deep Thinking Mode',
                trailing: CupertinoSwitch(
                  value: ai.deepThinkingEnabled,
                  activeTrackColor: TalkoraColors.iosGreen,
                  onChanged: (v) =>
                      ref.read(aiSettingsProvider.notifier).updateAdvanced(deepThinkingEnabled: v),
                ),
              ),
              IosSettingsRow(
                icon: CupertinoIcons.device_phone_portrait,
                iconColor: TalkoraColors.iosGreen,
                title: isAr ? 'التحكم بتطبيقات الهاتف' : 'Phone Apps Control',
                trailing: CupertinoSwitch(
                  value: ai.deviceControlEnabled,
                  activeTrackColor: TalkoraColors.iosGreen,
                  onChanged: (v) =>
                      ref.read(aiSettingsProvider.notifier).updateAdvanced(deviceControlEnabled: v),
                ),
              ),
              IosSettingsRow(
                icon: CupertinoIcons.layers_alt_fill,
                iconColor: TalkoraColors.iosIndigo,
                title: isAr ? 'استيراد قواعد بيانات GitHub و APIs' : 'GitHub & API Mega-Datasets Hub',
                onTap: () => context.push('/github-db'),
              ),
              IosSettingsRow(
                icon: CupertinoIcons.waveform_circle_fill,
                iconColor: TalkoraColors.iosPink,
                title: isAr ? 'محرك الصوت ($voiceStatus)' : 'Voice Engine ($voiceStatus)',
                onTap: () => context.push('/voice'),
              ),
            ],
          ),

          // Developer Info Section (YOSSEF JOO — WhatsApp 01029892573)
          IosGroupedSection(
            header: isAr ? 'بيانات المطور والدعم الفني' : 'DEVELOPER & SUPPORT',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IosIconBadge(
                          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                          color: TalkoraColors.iosGreen,
                          size: 46,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_devName, style: theme.textTheme.titleLarge),
                              Text(
                                isAr ? 'مطور تطبيق Nimo v6.0 Titan' : 'Lead Developer — Nimo v6.0 Titan',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                isAr ? 'واتساب: $_devWhatsApp' : 'WhatsApp: $_devWhatsApp',
                                style: theme.textTheme.titleMedium?.copyWith(color: TalkoraColors.iosGreen, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: TalkoraColors.iosGreen),
                            onPressed: () => bridge.openWhatsApp(
                              phone: _devWhatsApp,
                              message: 'مرحباً مهندس $_devName، أتواصل معك بخصوص تطبيق Nimo v6.0 Titan',
                            ),
                            icon: const Icon(CupertinoIcons.chat_bubble_fill, size: 18),
                            label: Text(isAr ? 'تواصل واتساب مباشر' : 'WhatsApp'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => bridge.dialPhone(_devWhatsApp),
                          icon: const Icon(CupertinoIcons.phone_fill),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: _devWhatsApp));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(isAr ? 'تم نسخ رقم المطور $_devWhatsApp' : 'Copied $_devWhatsApp')),
                            );
                          },
                          icon: const Icon(CupertinoIcons.doc_on_clipboard),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

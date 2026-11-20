import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/realistic_tts_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';

/// Nimo v6.0 Titan — Multi-Language AI Translator & Voice Idiom Decoder.
class TranslatorScreen extends ConsumerStatefulWidget {
  const TranslatorScreen({super.key});

  @override
  ConsumerState<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends ConsumerState<TranslatorScreen> {
  final TextEditingController _srcCtrl = TextEditingController();
  String _fromLang = 'English';
  String _toLang = 'Arabic';
  bool _loading = false;
  String? _output;
  String? _error;

  static const List<String> _langs = ['Arabic', 'English', 'French', 'German', 'Spanish', 'Turkish'];

  @override
  void dispose() {
    _srcCtrl.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _srcCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    NimoSoundFx.pop();

    setState(() {
      _loading = true;
      _error = null;
      _output = null;
    });

    final settings = ref.read(aiSettingsProvider);
    final service = ref.read(universalAiServiceProvider);
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';

    final res = await service.sendChat(
      settings: settings,
      systemPromptOverride:
          'You are an expert translator and idiom decoder. Translate the user text from $_fromLang into natural $_toLang.\n'
          'Provide:\n'
          '• Natural Translation\n'
          '• Idiom / Nuance Note (if any)\n'
          '• 2 Short Real-Life Example Sentences.',
      messages: [AiChatMessage(role: 'user', content: text, timestamp: DateTime.now())],
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _output = res.text;
        ref.read(learnerProfileProvider.notifier).addXp(10);
      } else if (res.error == 'MISSING_API_KEY') {
        _error = isAr
            ? 'أضف مفتاح API في الإعدادات أو فعّل التحويل التلقائي للعمل فوراً.'
            : 'Add an AI API key in Settings or enable Smart Fallback.';
      } else {
        _error = res.error;
      }
    });
  }

  void _speak(String text, String lang) {
    NimoSoundFx.click();
    final locale = lang == 'Arabic' ? 'ar-EG' : 'en-US';
    ref.read(realisticTtsProvider).speakHuman(
          text: text,
          aiSettings: ref.read(aiSettingsProvider),
          locale: locale,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'المترجم الذكي متعدد اللغات' : 'Smart AI Translator'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.slider_horizontal_3),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _fromLang,
                        isExpanded: true,
                        items: _langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                        onChanged: (v) => setState(() => _fromLang = v ?? 'English'),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {
                      NimoSoundFx.click();
                      setState(() {
                        final tmp = _fromLang;
                        _fromLang = _toLang;
                        _toLang = tmp;
                      });
                    },
                    icon: const Icon(CupertinoIcons.arrow_right_arrow_left, size: 18),
                  ),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _toLang,
                        isExpanded: true,
                        items: _langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                        onChanged: (v) => setState(() => _toLang = v ?? 'Arabic'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          IosGroupedSection(
            header: _fromLang.toUpperCase(),
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: _srcCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: isAr ? 'اكتب أو الصق النص المراد ترجمته...' : 'Enter or paste text to translate...',
                        suffixIcon: IconButton(
                          icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 19),
                          onPressed: () => NimoClipboardHelper.pasteIntoController(context, _srcCtrl, isAr: isAr),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _translate,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CupertinoActivityIndicator(color: Colors.white),
                                  )
                                : const Icon(CupertinoIcons.globe, size: 19),
                            label: Text(isAr ? 'ترجمة وشرح ذكي' : 'Translate & Decode'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: isAr ? 'نطق النص' : 'Speak',
                          onPressed: () {
                            if (_srcCtrl.text.trim().isNotEmpty) _speak(_srcCtrl.text.trim(), _fromLang);
                          },
                          icon: const Icon(CupertinoIcons.speaker_2_fill, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null)
            Card(
              color: TalkoraColors.iosOrange.withValues(alpha: 0.14),
              child: ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: () => context.push('/settings'),
                  child: Text(isAr ? 'الإعدادات' : 'Settings'),
                ),
              ),
            ),
          if (_output != null)
            IosGroupedSection(
              header: isAr ? 'الترجمة والأمثلة ($_toLang)' : 'TRANSLATION ($_toLang)',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_output!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _speak(_output!, _toLang),
                            icon: const Icon(CupertinoIcons.speaker_2_fill, size: 16),
                            label: Text(isAr ? 'نطق الترجمة' : 'Speak'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _output!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isAr ? 'تم النسخ' : 'Copied')),
                              );
                            },
                            icon: const Icon(CupertinoIcons.doc_on_doc, size: 17),
                            label: Text(isAr ? 'نسخ' : 'Copy'),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talkora_ai/app/router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

class TalkoraApp extends ConsumerStatefulWidget {
  const TalkoraApp({super.key});

  @override
  ConsumerState<TalkoraApp> createState() => _TalkoraAppState();
}

class _TalkoraAppState extends ConsumerState<TalkoraApp> {
  StreamSubscription<NativeVoiceEvent>? _bubbleSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(nimoLocalDbProvider.notifier).load();
      ref.read(githubKnowledgeProvider);
      _listenForFloatingBubblePrompts();
    });
  }

  void _listenForFloatingBubblePrompts() {
    final bridge = ref.read(nativeBridgeProvider);
    _bubbleSub = bridge.voiceEvents.listen((event) {
      if (event.type == 'bubble_prompt' && event.text.trim().isNotEmpty && mounted) {
        ref.read(chatPrefillPromptProvider.notifier).state = event.text.trim();
        ref.read(appRouterProvider).go('/chat');
      }
    });
    bridge.getPendingBubblePrompt().then((pending) {
      if (pending.trim().isNotEmpty && mounted) {
        ref.read(chatPrefillPromptProvider.notifier).state = pending.trim();
        ref.read(appRouterProvider).go('/chat');
      }
    });
  }

  @override
  void dispose() {
    _bubbleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiLocale = ref.watch(learnerProfileProvider.select((s) => s.uiLocale));
    final accentKey = ref.watch(learnerProfileProvider.select((s) => s.accentColorKey));
    final themeMode = ref.watch(learnerProfileProvider.select((s) => s.themeMode));
    final clickSound = ref.watch(learnerProfileProvider.select((s) => s.clickSoundEnabled));
    final router = ref.watch(appRouterProvider);

    NimoSoundFx.enabled = clickSound;
    final isArabic = uiLocale == 'ar';

    return MaterialApp.router(
      title: 'Nimo',
      debugShowCheckedModeBanner: false,
      theme: TalkoraTheme.light(isArabic: isArabic, accentKey: accentKey),
      darkTheme: TalkoraTheme.dark(isArabic: isArabic, accentKey: accentKey),
      themeMode: themeMode,
      locale: Locale(uiLocale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}

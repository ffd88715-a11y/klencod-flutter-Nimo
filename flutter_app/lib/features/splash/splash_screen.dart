import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Nimo v9.0 OmniControl — Ultra-Fast Matte Glass Intro Screen (1.15s crisp launch, tap to enter instantly).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _introCtrl;
  Timer? _navTimer;
  bool _navigated = false;

  static const List<String> _brandLetters = ['N', 'i', 'm', 'o'];

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();

    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted) NimoSoundFx.chime();
    });

    _navTimer = Timer(const Duration(milliseconds: 1150), _proceed);
  }

  void _proceed() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final onboarded = ref.read(learnerProfileProvider).onboardingCompleted;
    context.go(onboarded ? '/home' : '/onboarding');
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _introCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final localDb = ref.watch(nimoLocalDbProvider);
    final ai = ref.watch(aiSettingsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final isAr = s.isArabic;

    final emblemScale = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.0, 0.52, curve: Curves.easeOutBack),
    );
    final subtitleFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: isDark ? TalkoraColors.darkBackground : TalkoraColors.lightBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _proceed,
        child: SizedBox.expand(
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: isDark ? 0.14 : 0.10),
                          TalkoraColors.iosIndigo.withValues(alpha: 0.03),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: emblemScale,
                          child: Container(
                            width: 106,
                            height: 106,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  accent.withValues(alpha: 0.94),
                                  TalkoraColors.iosIndigo.withValues(alpha: 0.88),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.30),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 50),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _brandLetters.length; i++)
                                _AnimatedBrandLetter(
                                  letter: _brandLetters[i],
                                  controller: _introCtrl,
                                  start: 0.15 + (i * 0.08),
                                  end: (0.50 + (i * 0.08)).clamp(0.0, 1.0),
                                  accent: accent,
                                  isDark: isDark,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        FadeTransition(
                          opacity: subtitleFade,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.t('subtitle'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isDark ? TalkoraColors.darkSurface : accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: accent.withValues(alpha: 0.28), width: 0.8),
                                ),
                                child: Text(
                                  'Nimo v9.0 OmniControl • YOSSEF JOO',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isAr
                                    ? '${ai.activePreset.shortName} • ${localDb.totalRecords > 0 ? '${localDb.totalRecords} سجل جاهز' : 'تشغيل فائق السرعة...'}'
                                    : '${ai.activePreset.shortName} • ${localDb.totalRecords > 0 ? '${localDb.totalRecords} records ready' : 'Turbo launch...'}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedBrandLetter extends StatelessWidget {
  final String letter;
  final AnimationController controller;
  final double start;
  final double end;
  final Color accent;
  final bool isDark;

  const _AnimatedBrandLetter({
    required this.letter,
    required this.controller,
    required this.start,
    required this.end,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final v = anim.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * 20),
            child: Transform.scale(
              scale: 0.80 + (0.20 * v),
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [Colors.white, accent.withValues(alpha: 0.90)]
                      : [const Color(0xFF141824), accent],
                ).createShader(bounds),
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

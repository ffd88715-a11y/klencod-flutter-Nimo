import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';

/// Nimo v5.0 Ultra — Perfectly Centered, Eye-Friendly Matte Glass Intro Screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _introCtrl;
  late final AnimationController _sheenCtrl;
  Timer? _navTimer;
  bool _navigated = false;

  static const List<String> _brandLetters = ['N', 'i', 'm', 'o'];

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    )..forward();

    _sheenCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Warm up built-in DB and injected GitHub datasets immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(nimoLocalDbProvider.notifier).load();
      ref.read(githubKnowledgeProvider);
    });

    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (mounted) NimoSoundFx.chime();
    });

    _navTimer = Timer(const Duration(milliseconds: 2400), _proceed);
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
    _sheenCtrl.dispose();
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
      curve: const Interval(0.0, 0.48, curve: Curves.easeOutBack),
    );
    final subtitleFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.56, 1.0, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121417) : TalkoraColors.lightBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _proceed,
        child: SizedBox.expand(
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Subtle centered matte radial backdrop (eye-friendly, zero harsh neon)
                Center(
                  child: AnimatedBuilder(
                    animation: _sheenCtrl,
                    builder: (_, __) {
                      final pulse = 0.94 + 0.06 * math.sin(_sheenCtrl.value * 2 * math.pi);
                      return Transform.scale(
                        scale: pulse,
                        child: Container(
                          width: 300,
                          height: 300,
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
                      );
                    },
                  ),
                ),

                // Perfectly centered brand core
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Matte Liquid Glass Emblem
                        ScaleTransition(
                          scale: emblemScale,
                          child: AnimatedBuilder(
                            animation: _sheenCtrl,
                            builder: (_, __) {
                              final sweep = -1.6 + (_sheenCtrl.value * 3.2);
                              return Container(
                                width: 112,
                                height: 112,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withValues(alpha: 0.92),
                                      TalkoraColors.iosIndigo.withValues(alpha: 0.86),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.34),
                                    width: 1.3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
                                      blurRadius: 26,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      top: -36,
                                      left: -20,
                                      right: -20,
                                      height: 76,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.white.withValues(alpha: 0.32),
                                              Colors.white.withValues(alpha: 0.0),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(60),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Transform.rotate(
                                        angle: math.pi / 6,
                                        child: FractionallySizedBox(
                                          widthFactor: 0.38,
                                          alignment: Alignment(sweep, 0),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(alpha: 0.0),
                                                  Colors.white.withValues(alpha: 0.28),
                                                  Colors.white.withValues(alpha: 0.0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 52),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 26),

                        // Staggered Letter-by-Letter "Nimo" Animated Wordmark (strictly centered)
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < _brandLetters.length; i++)
                                _AnimatedBrandLetter(
                                  letter: _brandLetters[i],
                                  controller: _introCtrl,
                                  start: 0.22 + (i * 0.09),
                                  end: (0.55 + (i * 0.09)).clamp(0.0, 1.0),
                                  accent: accent,
                                  isDark: isDark,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Subtitle, Status Pills & Smooth Progress Indicator
                        FadeTransition(
                          opacity: subtitleFade,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                s.t('subtitle'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1A1D24)
                                      : accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.28),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  'Nimo v5.0 Ultra • YOSSEF JOO',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                isAr
                                    ? '${ai.activePreset.shortName} • ${localDb.totalRecords > 0 ? '${localDb.totalRecords} سجل معرفي جاهز' : 'جاري تجهيز قواعد المعرفة...'}'
                                    : '${ai.activePreset.shortName} • ${localDb.totalRecords > 0 ? '${localDb.totalRecords} records ready' : 'Loading knowledge engine...'}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: 150,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AnimatedBuilder(
                                    animation: _introCtrl,
                                    builder: (_, __) => LinearProgressIndicator(
                                      value: _introCtrl.value.clamp(0.08, 1.0),
                                      minHeight: 4,
                                      backgroundColor: accent.withValues(alpha: 0.16),
                                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Subtle bottom tap-to-enter hint
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 22,
                  child: FadeTransition(
                    opacity: subtitleFade,
                    child: Text(
                      isAr ? 'اضغط في أي مكان للمتابعة' : 'Tap anywhere to continue',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: (isDark
                                ? TalkoraColors.darkSecondaryText
                                : TalkoraColors.lightSecondaryText)
                            .withValues(alpha: 0.78),
                      ),
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
            offset: Offset(0, (1.0 - v) * 24),
            child: Transform.scale(
              scale: 0.76 + (0.24 * v),
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
                    fontSize: 52,
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

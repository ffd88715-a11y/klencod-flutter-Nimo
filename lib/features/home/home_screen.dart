import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/image_gen_service.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_animations.dart';

/// Nimo v8.0 Quantum — Locked-120fps Matte Home Hub with Instant Quick-Ask Bar,
/// AI Battle Arena Shortcut, Live Pulse Status & Staggered Feature Grid.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _quickAskCtrl = TextEditingController();

  @override
  void dispose() {
    _quickAskCtrl.dispose();
    super.dispose();
  }

  void _launchQuickAsk() {
    final txt = _quickAskCtrl.text.trim();
    if (txt.isEmpty) {
      context.go('/chat');
      return;
    }
    NimoSoundFx.pop();
    _quickAskCtrl.clear();
    ref.read(chatPrefillPromptProvider.notifier).state = txt;
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learnerProfileProvider);
    final ai = ref.watch(aiSettingsProvider);
    final localDb = ref.watch(nimoLocalDbProvider);
    final s = ref.watch(appStringsProvider);
    final isAr = s.isArabic;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalKnowledge = localDb.totalRecords;
    final progressRatio = (profile.speakingMinutesToday / profile.dailyTargetMinutes).clamp(0.0, 1.0);
    final imgRoute = ImageGenService.describeActiveKeyRoute(ai, isAr: isAr);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          cacheExtent: 600,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            // Top Bar + Live Pulse AI Model Pill
            NimoEntrance(
              child: Row(
                children: [
                  IosIconBadge(
                    icon: CupertinoIcons.sparkles,
                    color: theme.colorScheme.primary,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'Nimo • أهلاً ${profile.displayName}' : 'Nimo • Hi ${profile.displayName}',
                          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 19.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: () => context.push('/settings'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NimoLivePulseDot(
                                color: ai.isConfigured ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                                size: 7,
                                active: ai.isConfigured,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${ai.activePreset.shortName} • ${ai.activeModel}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: ai.isConfigured ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  NimoGlassTap(
                    onTap: () => context.push('/settings'),
                    child: const IosIconBadge(
                      icon: CupertinoIcons.gear_alt_fill,
                      color: TalkoraColors.iosIndigo,
                      size: 38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Instant Streaming Quick-Ask Bar
            NimoEntrance(
              delay: const Duration(milliseconds: 45),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.30),
                    width: 0.9,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.sparkles, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _quickAskCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _launchQuickAsk(),
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          hintText: isAr ? 'اسأل Nimo v8.0 سؤالاً ببث حي فوري...' : 'Ask Nimo v8.0 (Live Stream)...',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(36, 36),
                          shape: const CircleBorder(),
                        ),
                        onPressed: _launchQuickAsk,
                        child: const Icon(CupertinoIcons.arrow_up, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Lightweight Zero-Lag Hero Card
            NimoEntrance(
              delay: const Duration(milliseconds: 90),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      TalkoraColors.iosIndigo,
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.9),
                ),
                child: Column(
                  children: [
                    NimoGlassTap(
                      onTap: () => context.push('/voice'),
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                        ),
                        child: const Icon(CupertinoIcons.waveform, color: Colors.white, size: 34),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isAr ? 'Nimo v8.0 Quantum — سرعة فائقة وبث حي' : 'Nimo v8.0 Quantum — Live Streaming AI',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? 'مرتبط بـ $totalKnowledge سجل + ${ai.savedApiKeysCount} مفاتيح AI + نماذج 2026'
                          : 'Powered by $totalKnowledge records + ${ai.savedApiKeysCount} API keys + 2026 models',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: theme.colorScheme.primary,
                            ),
                            onPressed: () {
                              NimoSoundFx.click();
                              context.push('/voice');
                            },
                            icon: const Icon(CupertinoIcons.mic_fill, size: 18),
                            label: Text(
                              isAr ? 'صوت لايف' : 'Live Voice',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.20),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              NimoSoundFx.click();
                              context.go('/chat');
                            },
                            icon: const Icon(CupertinoIcons.sparkles, size: 18),
                            label: Text(
                              isAr ? 'محادثة حية' : 'Live Chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Nimo v8.0 Quantum Super Suite Grid
            Text(
              isAr ? 'قدرات Nimo v8.0 Quantum' : 'Nimo v8.0 Quantum Suite',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            NimoEntrance(
              delay: const Duration(milliseconds: 130),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.32,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _IosFeatureTile(
                    icon: CupertinoIcons.bolt_fill,
                    color: TalkoraColors.iosOrange,
                    title: isAr ? 'ساحة مقارنة AI' : 'AI Battle Arena',
                    subtitle: isAr ? 'قارن نموذجين معاً فوراً' : 'Compare 2 models live',
                    onTap: () => context.push('/arena'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.lock_shield_fill,
                    color: TalkoraColors.iosBlue,
                    title: isAr ? 'خزنة مفاتيح AI' : 'AI Key Vault',
                    subtitle: isAr ? 'نماذج 2026 وفحص فوري' : '2026 models & health',
                    onTap: () => context.push('/settings'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.chevron_left_slash_chevron_right,
                    color: TalkoraColors.iosTeal,
                    title: isAr ? 'مختبر البرمجة Pro' : 'Coding Lab Pro',
                    subtitle: isAr ? 'معاينة كود حية + Console' : 'Live Preview + Console',
                    onTap: () => context.push('/coding-lab'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                    color: TalkoraColors.iosPink,
                    title: isAr ? 'استوديو الصور Pro' : 'AI Image Studio Pro',
                    subtitle: imgRoute,
                    onTap: () => context.push('/image-studio'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.layers_alt_fill,
                    color: TalkoraColors.iosIndigo,
                    title: isAr ? 'قواعد البيانات الذكية' : 'Smart Databases',
                    subtitle: isAr ? '$totalKnowledge سجل جاهز' : '$totalKnowledge records',
                    onTap: () => context.push('/github-db'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.device_phone_portrait,
                    color: TalkoraColors.iosGreen,
                    title: isAr ? 'إدارة الهاتف والتطبيقات' : 'Phone Manager',
                    subtitle: isAr ? 'فتح التطبيقات والأوامر' : 'Apps, Torch & System',
                    onTap: () => context.push('/device-hub'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.globe,
                    color: TalkoraColors.iosPurple,
                    title: s.t('translator'),
                    subtitle: isAr ? 'ترجمة وتعبيرات أصلية' : 'Idioms & Examples',
                    onTap: () => context.push('/translator'),
                  ),
                  _IosFeatureTile(
                    icon: CupertinoIcons.book_fill,
                    color: TalkoraColors.iosRed,
                    title: isAr ? 'التدريب والمواقف' : 'Practice & Roleplay',
                    subtitle: isAr ? 'نطق وقواعد ومحادثة' : 'Grammar & Scenarios',
                    onTap: () => context.push('/practice-hub'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Animated Progress Card
            NimoEntrance(
              delay: const Duration(milliseconds: 170),
              child: NimoGlassTap(
                onTap: () => context.push('/progress'),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isAr ? 'تقدمك اليومي في Nimo' : 'Nimo Daily Progress',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              '${profile.speakingMinutesToday} / ${profile.dailyTargetMinutes} ${isAr ? 'د' : 'min'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: progressRatio, minHeight: 7),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _BentoStat(label: isAr ? 'السجلات' : 'Records', value: totalKnowledge),
                            _BentoStat(label: isAr ? 'المفاتيح' : 'AI Keys', value: ai.savedApiKeysCount),
                            _BentoStat(label: isAr ? 'السلسلة' : 'Streak', value: profile.streakDays, suffix: 'd'),
                            _BentoStat(label: 'XP', value: profile.xpPoints),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Developer Contact Banner (YOSSEF JOO • WhatsApp 01029892573)
            NimoGlassTap(
              onTap: () => ref.read(nativeBridgeProvider).openWhatsApp(
                    phone: '01029892573',
                    message: 'مرحباً مهندس YOSSEF JOO، أتواصل معك من داخل تطبيق Nimo v8.0 Quantum',
                  ),
              child: Card(
                child: ListTile(
                  leading: const IosIconBadge(
                    icon: CupertinoIcons.chat_bubble_fill,
                    color: TalkoraColors.iosGreen,
                    size: 38,
                  ),
                  title: const Text('YOSSEF JOO', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    isAr ? 'مطور Nimo v8.0 Quantum • واتساب: 01029892573' : 'Nimo v8.0 Quantum Developer • WhatsApp: 01029892573',
                  ),
                  trailing: const Icon(CupertinoIcons.arrow_up_right_circle_fill, color: TalkoraColors.iosGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BentoStat extends StatelessWidget {
  final String label;
  final int value;
  final String suffix;
  const _BentoStat({required this.label, required this.value, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NimoAnimatedCounter(
          value: value,
          suffix: suffix,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _IosFeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _IosFeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NimoGlassTap(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IosIconBadge(icon: icon, color: color, size: 36),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

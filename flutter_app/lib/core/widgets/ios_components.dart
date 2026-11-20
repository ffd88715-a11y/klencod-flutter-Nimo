import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';

/// Authentic iOS Inset Grouped Section with subtle header, hairline dividers, and footer.
class IosGroupedSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const IosGroupedSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 20),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? TalkoraColors.darkSurface : TalkoraColors.lightSurface;
    final dividerColor = isDark ? TalkoraColors.darkSeparator : TalkoraColors.lightSeparator;
    final labelColor = isDark ? TalkoraColors.darkSecondaryText : TalkoraColors.lightSecondaryText;

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null && header!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: labelColor,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: dividerColor.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (footer != null && footer!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: labelColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nimo v7.0 Apex Turbo Glass Icon Badge — ultra-lightweight GPU-cached StatelessWidget!
/// Eliminates 15+ simultaneous infinite AnimationControllers per screen for buttery 60/120fps scrolling.
class IosIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool animatedGlass;

  const IosIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
    this.animatedGlass = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: isDark ? 0.88 : 0.94),
              color.withValues(alpha: isDark ? 0.54 : 0.72),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.24 : 0.50),
            width: 0.85,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.18 : 0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Crisp frosted top glass highlight (zero per-frame CPU cost)
            Positioned(
              top: -size * 0.35,
              left: -size * 0.2,
              right: -size * 0.2,
              height: size * 0.70,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.34),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
            Icon(icon, color: Colors.white, size: size * 0.56),
          ],
        ),
      ),
    );
  }
}

/// Interactive Glass Press Wrapper with smooth spring scale + click sound.
class NimoGlassTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  const NimoGlassTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
  });

  @override
  State<NimoGlassTap> createState() => _NimoGlassTapState();
}

class _NimoGlassTapState extends State<NimoGlassTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onLongPress,
      onTap: widget.onTap == null
          ? null
          : () {
              NimoSoundFx.click();
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Authentic iOS Settings Row with Turbo Glass icon, title, subtitle/value, click sound, and chevron.
class IosSettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  const IosSettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailingValue,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor = isDark ? TalkoraColors.darkSecondaryText : TalkoraColors.lightSecondaryText;

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              NimoSoundFx.click();
              onTap?.call();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            IosIconBadge(icon: icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: destructive ? TalkoraColors.iosRed : null,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (trailingValue != null) ...[
              const SizedBox(width: 8),
              Flexible(
                flex: 0,
                child: Text(
                  trailingValue!,
                  style: TextStyle(fontSize: 14.5, color: secondaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: secondaryColor.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS Status Pill Badge (e.g., Active AI Model indicator) with subtle glass border.
class IosStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  const IosStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return NimoGlassTap(onTap: onTap, child: child);
  }
}

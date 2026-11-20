import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Nimo v7.0 Apex — Ultra-Lightweight 60/120fps Motion & Animation Toolkit.
/// Every animation is GPU-composited (Opacity/Transform) and auto-disposes cleanly
/// so the app stays buttery-fast with zero idle CPU drain.

/// Smooth staggered slide-up + fade-in entrance animation that runs once on mount.
class NimoEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final double beginScale;

  const NimoEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.offsetY = 18.0,
    this.beginScale = 0.97,
  });

  @override
  State<NimoEntrance> createState() => _NimoEntranceState();
}

class _NimoEntranceState extends State<NimoEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slide = Tween<double>(begin: widget.offsetY, end: 0.0).animate(curved);
    _scale = Tween<double>(begin: widget.beginScale, end: 1.0).animate(curved);

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: Transform.scale(
              scale: _scale.value,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Smooth 3-dot wave AI thinking indicator (zero heavy spinners).
class NimoThinkingWave extends StatefulWidget {
  final Color color;
  final double dotSize;

  const NimoThinkingWave({
    super.key,
    required this.color,
    this.dotSize = 7.0,
  });

  @override
  State<NimoThinkingWave> createState() => _NimoThinkingWaveState();
}

class _NimoThinkingWaveState extends State<NimoThinkingWave> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value * 2 * math.pi) - (i * 0.85);
              final wave = (math.sin(phase) + 1) / 2; // 0..1
              final dy = -wave * 4.5;
              final scale = 0.78 + (wave * 0.34);
              final alpha = 0.45 + (wave * 0.55);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: alpha),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Smooth animated integer counter for dashboard KPIs & stats.
class NimoAnimatedCounter extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const NimoAnimatedCounter({
    super.key,
    required this.value,
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 520),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, val, _) {
        return Text('${val.round()}$suffix', style: style);
      },
    );
  }
}

/// Subtle breathing status dot (active only when [active] is true).
class NimoLivePulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;

  const NimoLivePulseDot({
    super.key,
    required this.color,
    this.size = 8.0,
    this.active = true,
  });

  @override
  State<NimoLivePulseDot> createState() => _NimoLivePulseDotState();
}

class _NimoLivePulseDotState extends State<NimoLivePulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant NimoLivePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final v = _ctrl.value;
          return SizedBox(
            width: widget.size * 1.9,
            height: widget.size * 1.9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: widget.size * (1.0 + v * 0.85),
                  height: widget.size * (1.0 + v * 0.85),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: (1.0 - v) * 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

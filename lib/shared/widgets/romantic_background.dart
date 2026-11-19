import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// A romantic ambient background widget featuring soft glowing orbs,
/// subtle floating hearts, and dreamy gradients.
class RomanticBackground extends StatefulWidget {
  const RomanticBackground({
    super.key,
    required this.child,
    this.showFloatingHearts = true,
    this.primaryGlowColor,
    this.secondaryGlowColor,
  });

  final Widget child;
  final bool showFloatingHearts;
  final Color? primaryGlowColor;
  final Color? secondaryGlowColor;

  @override
  State<RomanticBackground> createState() => _RomanticBackgroundState();
}

class _RomanticBackgroundState extends State<RomanticBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryGlowColor ?? AppColors.romanticRose;
    final secondaryColor = widget.secondaryGlowColor ?? AppColors.primary;

    return Stack(
      children: [
        // 1. Soft romantic multi-tone base gradient
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFFF6F9),
                  Color(0xFFF9F3FF),
                  Color(0xFFF6F9FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),

        // 2. Animated glowing ambient orbs
        AnimatedBuilder(
          animation: _animController,
          builder: (context, _) {
            final t = _animController.value;
            final offset1 = math.sin(t * math.pi) * 20.0;
            final offset2 = math.cos(t * math.pi) * 25.0;

            return Stack(
              children: [
                // Top-right romantic rose orb
                Positioned(
                  top: -60 + offset1,
                  right: -40 + offset2,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primaryColor.withOpacity(0.22),
                          primaryColor.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Center-left amethyst romantic glow orb
                Positioned(
                  top: 220 - offset2,
                  left: -70 + offset1,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          secondaryColor.withOpacity(0.18),
                          secondaryColor.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom-right sunset warm glow orb
                Positioned(
                  bottom: -50 + offset1,
                  right: -30 - offset2,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF8DA1).withOpacity(0.20),
                          const Color(0xFFFF8DA1).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // 3. Subtle floating heart accents (lightweight, non-distracting)
        if (widget.showFloatingHearts)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.12,
                child: CustomPaint(
                  painter: _FloatingHeartsPainter(),
                ),
              ),
            ),
          ),

        // 4. Content
        widget.child,
      ],
    );
  }
}

class _FloatingHeartsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8498A)
      ..style = PaintingStyle.fill;

    // Fixed pleasant romantic positions
    final hearts = [
      Offset(size.width * 0.12, size.height * 0.16),
      Offset(size.width * 0.85, size.height * 0.22),
      Offset(size.width * 0.20, size.height * 0.65),
      Offset(size.width * 0.88, size.height * 0.72),
      Offset(size.width * 0.75, size.height * 0.45),
      Offset(size.width * 0.08, size.height * 0.88),
    ];

    for (int i = 0; i < hearts.length; i++) {
      final pos = hearts[i];
      final scale = (i % 2 == 0) ? 0.7 : 0.9;
      _drawMiniHeart(canvas, pos, scale, paint);
    }
  }

  void _drawMiniHeart(Canvas canvas, Offset center, double scale, Paint paint) {
    final path = Path();
    final width = 16.0 * scale;
    final height = 16.0 * scale;

    path.moveTo(center.dx, center.dy + height * 0.25);
    path.cubicTo(
      center.dx, center.dy,
      center.dx - width * 0.5, center.dy,
      center.dx - width * 0.5, center.dy + height * 0.35,
    );
    path.cubicTo(
      center.dx - width * 0.5, center.dy + height * 0.6,
      center.dx, center.dy + height * 0.85,
      center.dx, center.dy + height,
    );
    path.cubicTo(
      center.dx, center.dy + height * 0.85,
      center.dx + width * 0.5, center.dy + height * 0.6,
      center.dx + width * 0.5, center.dy + height * 0.35,
    );
    path.cubicTo(
      center.dx + width * 0.5, center.dy,
      center.dx, center.dy,
      center.dx, center.dy + height * 0.25,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

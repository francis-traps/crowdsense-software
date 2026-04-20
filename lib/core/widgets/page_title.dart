import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui' as ui;

class PageTitle extends StatefulWidget {
  final String title;
  final String? subtitle;

  const PageTitle({super.key, required this.title, this.subtitle});

  @override
  State<PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<PageTitle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // High-performance entrance reveal
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    
    // Trigger the sweep once on entry
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title.toUpperCase(),
              style: GoogleFonts.rajdhani(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: colorScheme.onSurface,
                shadows: [
                  Shadow(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 0),
              Text(
                widget.subtitle!.toUpperCase(),
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 48,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _HeartbeatPainter(
                    color: const Color(0xFFFF0000), // Hyper-vibrant Neon Red
                    progress: _animation.value,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  final Color color;
  final double progress;

  _HeartbeatPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    final ambientGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0);

    final path = Path();
    double startY = size.height / 2;
    path.moveTo(0, startY);

    // Initial flat line
    double x = size.width * 0.12;
    path.lineTo(x, startY);

    // First small dip
    x += 10;
    path.lineTo(x, startY + 8);

    // High peak
    x += 16;
    path.lineTo(x, startY - 20);

    // Deep dip
    x += 18;
    path.lineTo(x, startY + 20);

    // Rebound up
    x += 12;
    path.lineTo(x, startY - 8);

    // Small stabilization wave
    x += 8;
    path.lineTo(x, startY + 4);

    // Return to flat line
    x += 10;
    path.lineTo(x, startY);

    // Extended flat line
    // Extended flat line - Shortened slightly to allow glow room at the end
    path.lineTo(size.width - 12, startY);

    // Compute metrics to animate the EKG sweep
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    
    final metric = metrics.first;
    final totalLength = metric.length;
    final currentLength = totalLength * progress;
    
    // Reveal path from start to current progress
    final extractPath = metric.extractPath(0.0, currentLength);
    
    // Create a dynamic gradient that follows the 'scan' head
    // This gives it that hospital monitor 'leading edge' glow
    final sweepGradient = ui.Gradient.linear(
      Offset(0, startY),
      Offset(size.width, startY),
      [
        color.withValues(alpha: 0.95), // Solid consistent trail
        color, // Brightest scan head
        color.withValues(alpha: 0.0), // Hidden ahead
      ],
      [
        (progress - 0.02).clamp(0.0, 1.0),
        progress.clamp(0.0, 1.0),
        (progress + 0.001).clamp(0.0, 1.0),
      ],
    );

    paint.shader = sweepGradient;
    
    final glowSweepGradient = ui.Gradient.linear(
      Offset(0, startY),
      Offset(size.width, startY),
      [
        color.withValues(alpha: 0.5),  // Consistent glowing body
        color, // Brightest scan head
        color.withValues(alpha: 0.0), // Hidden ahead
      ],
      [
        (progress - 0.05).clamp(0.0, 1.0),
        progress.clamp(0.0, 1.0),
        (progress + 0.001).clamp(0.0, 1.0),
      ],
    );
    
    glowPaint.shader = glowSweepGradient;
    ambientGlowPaint.shader = glowSweepGradient;

    canvas.drawPath(extractPath, ambientGlowPaint);
    canvas.drawPath(extractPath, glowPaint);
    canvas.drawPath(extractPath, paint);
    
    // Add a bright dot 'blip' at the tip for the BPM look
    if (progress > 0 && progress < 1.0) {
      final tangent = metric.getTangentForOffset(currentLength);
      if (tangent != null) {
        final pos = tangent.position;
        // Outer glow
        canvas.drawCircle(
          pos, 
          5.0, 
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        );
        // Inner core
        canvas.drawCircle(
          pos, 
          2.0, 
          Paint()..color = Colors.white
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

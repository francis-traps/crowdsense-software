import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SecondaryGeometricBackground extends StatelessWidget {
  final Widget child;

  const SecondaryGeometricBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Base Gradient
        Container(
          decoration: BoxDecoration(
            gradient: isDark 
                ? LinearGradient(colors: [AppColors.backgroundDark, AppColors.surfaceDark], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : const LinearGradient(colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        
        // Geometric Shapes
        CustomPaint(
          painter: _SecondaryGeometricPainter(isDark: isDark),
          size: Size.infinite,
        ),
        
        // Content
        child,
      ],
    );
  }
}

class _SecondaryGeometricPainter extends CustomPainter {
  final bool isDark;

  _SecondaryGeometricPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // 1. Large Polygon (Bottom Right focused)
    // Red/Orange geometric slice
    final path1 = Path();
    path1.moveTo(0, size.height); // Bottom left
    path1.lineTo(size.width, size.height * 0.4); // Angle up towards right
    path1.lineTo(size.width, size.height); // Bottom right corner
    path1.close();

    paint.shader = LinearGradient(
      colors: [
        AppColors.primaryBlue.withValues(alpha: isDark ? 0.12 : 0.08),
        AppColors.accentCyan.withValues(alpha: isDark ? 0.05 : 0.04),
      ],
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path1, paint);

    // 2. Secondary Polygon (Top Left)
    // Deep purple / blue angular slice
    final path2 = Path();
    path2.moveTo(0, 0); // Top left
    path2.lineTo(size.width * 0.6, 0); // Angle across top
    path2.lineTo(0, size.height * 0.5); // Angle down left
    path2.close();

    paint.shader = LinearGradient(
      colors: [
        AppColors.accentBlue.withValues(alpha: isDark ? 0.1 : 0.08),
        AppColors.primaryBlue.withValues(alpha: isDark ? 0.04 : 0.03),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path2, paint);

    // We removed the glowing circles and rely purely on geometric angular layers.
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _SecondaryGeometricPainter) {
      return oldDelegate.isDark != isDark;
    }
    return true;
  }
}

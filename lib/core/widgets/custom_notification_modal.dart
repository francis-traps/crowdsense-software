import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomNotificationModal {
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required bool isSuccess,
    bool isDestructive = false,
    Color? customColor,
    IconData? customIcon,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // Auto-dismiss after 2.5 seconds
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final Color surfaceColor = isDark ? const Color(0xFF1E2433) : Colors.white;
        final Color primaryColor = customColor ?? (isDestructive ? AppColors.statusDanger : (isSuccess ? AppColors.statusSafe : AppColors.statusDanger));
        final IconData primaryIcon = customIcon ?? (isDestructive ? Icons.delete_outline_rounded : (isSuccess ? Icons.check_circle_rounded : Icons.error_rounded));

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: primaryColor.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.2),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(primaryIcon, color: primaryColor, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20, 
                    fontWeight: FontWeight.w900, 
                    letterSpacing: 2.0,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isSuccess ? "VERIFIED SUCCESS" : "VERIFICATION FAILED",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14, 
                    height: 1.5,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 8,
                      shadowColor: primaryColor.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      "DISMISS", 
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

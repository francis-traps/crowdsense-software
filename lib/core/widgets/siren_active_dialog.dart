import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../providers/siren_provider.dart';
import 'custom_notification_modal.dart';

class SirenActiveDialog {
  static void show(BuildContext context, SirenProvider sirenProvider) {
    final title = sirenProvider.activeSirenTitle ?? "EMERGENCY";
    final icon = sirenProvider.activeSirenIcon ?? Icons.campaign_rounded;
    final color = sirenProvider.activeSirenColor ?? AppColors.statusDanger;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161B26) : Colors.white,
          elevation: 30,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: isDark ? Colors.white38 : Colors.black38),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: color.withValues(alpha: 0.2), width: 1),
                ),
                child: Icon(icon, color: color, size: 56),
              ),
              const SizedBox(height: 20),
              Text(
                "CRITICAL ALERT",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.0,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "$title\nIS ACTIVE",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontSize: 24,
                  height: 1.1,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "IN PROGRESS",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: isDark ? Colors.white24 : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "General evacuation alarms are currently sounding across the facility. All zones are locked for emergency clearance.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(30, 10, 30, 24),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding:
              const EdgeInsets.only(bottom: 30, left: 30, right: 30),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  sirenProvider.terminateSiren();
                  Navigator.pop(context);
                  CustomNotificationModal.show(
                    context: context,
                    title: "SIGNAL TERMINATED",
                    message: "$title has been DEACTIVATED successfully.",
                    isSuccess: true,
                    customColor: AppColors.primaryBlue,
                    customIcon: Icons.volume_off_rounded,
                  );
                },
                icon: const Icon(Icons.power_settings_new_rounded, size: 24),
                label: const Text(
                  "TERMINATE SIREN",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.1),
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: color.withValues(alpha: 0.5), width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

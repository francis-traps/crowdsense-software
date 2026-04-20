import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../../core/theme/app_colors.dart';

class PeopleCounterCard extends StatelessWidget {
  final List<Map<String, dynamic>> deviceData;
  final int currentIndex;
  final PageController pageController;
  final Function(int) onPageChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const PeopleCounterCard({
    super.key,
    required this.deviceData,
    required this.currentIndex,
    required this.pageController,
    required this.onPageChanged,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final currentData = deviceData[currentIndex];
    final String connectionState = currentData['connectionState'] ?? 'NEVER SEEN';
    
    Color statusColor;
    if (connectionState == 'CONNECTED') {
      statusColor = AppColors.statusSafe;
    } else if (connectionState == 'DISCONNECTED') {
      statusColor = AppColors.statusDanger;
    } else {
      statusColor = Theme.of(context).colorScheme.onSurfaceVariant; // Gray color for never seen
    }
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "Area Crowd Count",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white.withValues(alpha: 0.5) : colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 6, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          connectionState,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: Stack(
                  children: [
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: PageView.builder(
                        controller: pageController,
                        onPageChanged: onPageChanged,
                        clipBehavior: Clip.none,
                        itemBuilder: (context, index) {
                          final data = deviceData[index % deviceData.length];
                          final String pageLocation = data['location'];
                          final int pageEntries = data['entries'] ?? 0;
                          final int pageExits = data['exits'] ?? 0;
                          final int currentInside = (pageEntries - pageExits).clamp(0, 99999);
                          final bool isNotClear = currentInside > 0;
                          final badgeColor = isNotClear ? AppColors.statusWarning : AppColors.statusSafe;
    
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        pageLocation,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: colorScheme.onSurface,
                                          letterSpacing: -0.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    RepaintBoundary(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(30),
                                          border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: badgeColor.withValues(alpha: isDark ? 0.2 : 0.12),
                                              blurRadius: 15,
                                              spreadRadius: 0,
                                            ),
                                          ]
                                        ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isNotClear ? "NOT CLEAR" : "CLEAR",
                                            style: TextStyle(
                                              color: badgeColor,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 10,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            isNotClear ? Icons.priority_high_rounded : Icons.check_rounded,
                                            size: 14,
                                            color: badgeColor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                                const SizedBox(height: 24),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: SizedBox(
                                  height: 160,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildMetricCard("Entries", currentInside, AppColors.statusSafe, isDark),
                                      const SizedBox(width: 12),
                                      _buildMetricCard("Exits", data['exits'] ?? 0, AppColors.statusDanger, isDark),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                        );
                      },
                      ),
                    ),
                    Positioned(
                      left: -16,
                      top: 60,
                      height: 160,
                      child: IconButton(
                        onPressed: onPrevious,
                        icon: Icon(Icons.chevron_left, color: colorScheme.onSurface.withValues(alpha: 0.7), size: 32),
                      ),
                    ),
                    Positioned(
                      right: -16,
                      top: 60,
                      height: 160,
                      child: IconButton(
                        onPressed: onNext,
                        icon: Icon(Icons.chevron_right, color: colorScheme.onSurface.withValues(alpha: 0.7), size: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, int value, Color color, bool isDark) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.35 : 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: isDark ? 0.1 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == 0 ? '0' : value.toString(),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : color.withValues(alpha: 0.9),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: (isDark ? Colors.white : color).withValues(alpha: 0.6),
                    letterSpacing: 1.2,
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

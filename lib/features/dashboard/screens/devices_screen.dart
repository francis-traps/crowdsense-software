import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart'; // Added for date formatting later
import 'package:provider/provider.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/page_title.dart';
import '../widgets/device_management_modal.dart';

class DeviceLog {
  final String id;
  final IconData icon;
  final String title;
  final String message;
  final DateTime dateTime;
  final Color iconColor;
  bool isUnread;
  final String sensorType; // 'ToF', 'Flame', 'Smoke', 'Temp'
  final String priority; // 'High', 'Mid', 'Low'
  // New detailed fields
  String currentStatus; // 'Active', 'Acknowledged', 'Resolved', 'False Alarm'
  final Duration? duration;
  final String? peakSensorReading;
  final String? thresholdLimit;
  final bool isMainsPower;
  final int? batteryPercentage;
  final bool? relayTriggered;
  final bool? sirenActivated;
  final List<String> networkActions;
  final String specificZone;

  DeviceLog({
    required this.id,
    required this.icon,
    required this.title,
    required this.message,
    required this.dateTime,
    required this.iconColor,
    required this.isUnread,
    required this.sensorType,
    required this.priority,
    this.currentStatus = 'Active',
    this.duration,
    this.peakSensorReading,
    this.thresholdLimit,
    this.isMainsPower = true,
    this.batteryPercentage,
    this.relayTriggered,
    this.sirenActivated,
    this.networkActions = const [],
    required this.specificZone,
  });
}

class DevicesScreen extends StatefulWidget {
  final List<DeviceLog> logs;
  final String? highlightedLogId;
  final GlobalKey? highlightedItemKey;
  final ScrollController? parentScrollController;
  final int onlineCount;
  final int offlineCount;

  const DevicesScreen({
    super.key,
    required this.logs,
    this.highlightedLogId,
    this.highlightedItemKey,
    this.parentScrollController,
    this.onlineCount = 0,
    this.offlineCount = 0,
    this.activeIndex = 3,
  });

  final int activeIndex;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  // Filter State
  DateTime? selectedFilterDate;
  List<String> selectedSensorTypes = [];
  List<String> selectedPriorities = [];
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider>();
    final isAdmin = userProv.role.toLowerCase() == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageTitle(
          key: ValueKey('Page_${widget.activeIndex}'),
          title: "Devices"
        ),
        const SizedBox(height: 16),
        
        // Online / Offline count
        Row(
          children: [
            Expanded(
              child: _GlowingStatusCard(title: "Online Devices", count: widget.onlineCount, color: AppColors.statusSafe),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GlowingStatusCard(title: "Offline Devices", count: widget.offlineCount, color: AppColors.statusDanger),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            // Power Management Card
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: InkWell(
                    onTap: () => _showDeviceDetailsModal(context, "Power Management"),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      height: 140,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.statusSafe.withValues(alpha: 0.15),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.statusSafe.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.bolt_rounded, color: AppColors.statusSafe, size: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "POWER",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: isAdmin
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.center,
                              children: [
                                Text(
                                  "UPS & AC",
                                  textAlign: isAdmin
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Status Monitor",
                                  textAlign: isAdmin
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.4),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(width: 12),
              // Device Management Card
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const DeviceManagementModal(),
                        );
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        height: 140,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        decoration: BoxDecoration(
                          color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.15),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.settings_suggest_rounded, color: AppColors.primaryBlue, size: 14),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "DEVICES",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 10,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Nodes Management",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Configuration",
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 32),
        // Logs Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.list_alt, color: AppColors.primaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  "Device Activity Logs",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            _BouncingFilterButton(onTap: _openFilterModal),
          ],
        ),
        const SizedBox(height: 4),
        
        ..._buildFilteredLogWidgets(),
      ],
    );
  }

  void _openFilterModal() {
    // Temporary variables for modal's local state before applying
    DateTime? tempDate = selectedFilterDate;
    List<String> tempSensors = List.from(selectedSensorTypes);
    List<String> tempPriorities = List.from(selectedPriorities);

    showDialog(
      context: context,
      barrierColor: Colors.black45, // Translucent underlying barrier
      builder: (context) {
        return TweenAnimationBuilder(
          duration: const Duration(milliseconds: 450), // Slower animation as requested
          tween: Tween<double>(begin: 0.0, end: 1.0),
          curve: Curves.easeOutBack,
          builder: (context, double value, child) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0 * value, sigmaY: 8.0 * value),
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setModalState) {
                      return Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.1),
                                  blurRadius: Theme.of(context).brightness == Brightness.dark ? 20 : 30,
                                  offset: Offset(0, Theme.of(context).brightness == Brightness.dark ? 10 : 15),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Filter Logs",
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setModalState(() {
                                                tempDate = null;
                                                tempSensors.clear();
                                                tempPriorities.clear();
                                              });
                                            },
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: const Text("Clear All", style: TextStyle(color: AppColors.statusDanger)),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            onPressed: () => Navigator.pop(context),
                                            icon: const Icon(Icons.close, color: AppColors.textGrey),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                      
                      // 1. DATE FILTER
                      Text("Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: tempDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: AppColors.primaryBlue,
                                    onPrimary: Colors.white,
                                    surface: AppColors.surfaceDark,
                                    onSurface: AppColors.textLight,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setModalState(() {
                              tempDate = picked;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tempDate != null ? DateFormat('MMMM d, yyyy').format(tempDate!) : "Select Date",
                                style: TextStyle(color: tempDate != null ? AppColors.textLight : AppColors.textGrey),
                              ),
                              const Icon(Icons.calendar_today, color: AppColors.textGrey, size: 20),
                            ],
                          ),
                        ),
                      ),
                      if (tempDate != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setModalState(() => tempDate = null),
                            child: Text("Clear Date", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                          ),
                        )
                      else
                        const SizedBox(height: 24),

                      // 2. SENSOR TYPE FILTER
                      Text("Sensor Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['ToF', 'Flame', 'Smoke', 'Temp', 'Power'].map((sensor) {
                          final isSelected = tempSensors.contains(sensor);
                          return FilterChip(
                            label: Text(sensor),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setModalState(() {
                                if (selected) {
                                  tempSensors.add(sensor);
                                } else {
                                  tempSensors.remove(sensor);
                                }
                              });
                            },
                            selectedColor: AppColors.primaryBlue.withValues(alpha: 0.3),
                            checkmarkColor: AppColors.primaryBlue,
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isSelected ? AppColors.primaryBlue : Colors.white24),
                            ),
                            labelStyle: TextStyle(color: isSelected ? AppColors.primaryBlue : Theme.of(context).colorScheme.onSurfaceVariant),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // 3. PRIORITY FILTER
                      Text("Emergency Priority", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: ['High', 'Mid', 'Low'].map((priority) {
                          final isSelected = tempPriorities.contains(priority);
                          Color pColor;
                          if (priority == 'High') pColor = AppColors.statusDanger;
                          else if (priority == 'Mid') pColor = AppColors.statusWarning;
                          else pColor = AppColors.statusSafe;

                          return FilterChip(
                            label: Text(priority),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setModalState(() {
                                if (selected) {
                                  tempPriorities.add(priority);
                                } else {
                                  tempPriorities.remove(priority);
                                }
                              });
                            },
                            selectedColor: pColor.withValues(alpha: 0.2),
                            checkmarkColor: pColor,
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isSelected ? pColor : Colors.white24),
                            ),
                            labelStyle: TextStyle(color: isSelected ? pColor : Theme.of(context).colorScheme.onSurfaceVariant),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 32),
                      
                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              selectedFilterDate = tempDate;
                              selectedSensorTypes = List.from(tempSensors);
                              selectedPriorities = List.from(tempPriorities);
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text(
                            "Apply Filters",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
          },
        );
      },
    );
  }
 
  List<Widget> _buildFilteredLogWidgets() {
    // 1. Filter Logs
    List<DeviceLog> filteredLogs = widget.logs.where((log) {
      bool matchesDate = true;
      if (selectedFilterDate != null) {
        matchesDate = log.dateTime.year == selectedFilterDate!.year &&
                      log.dateTime.month == selectedFilterDate!.month &&
                      log.dateTime.day == selectedFilterDate!.day;
      }
      
      bool matchesSensor = true;
      if (selectedSensorTypes.isNotEmpty) {
        matchesSensor = selectedSensorTypes.contains(log.sensorType);
      }

      bool matchesPriority = true;
      if (selectedPriorities.isNotEmpty) {
        matchesPriority = selectedPriorities.contains(log.priority);
      }

      return matchesDate && matchesSensor && matchesPriority;
    }).toList();

    if (filteredLogs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              "No logs match the current filters.",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
            ),
          ),
        ),
      ];
    }

    // 2. Group by Date
    Map<String, List<DeviceLog>> groupedLogs = {};
    for (var log in filteredLogs) {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final logDate = DateTime(log.dateTime.year, log.dateTime.month, log.dateTime.day);
      final difference = todayDate.difference(logDate).inDays;
      
      String relativeTimeStr;

      if (difference == 0) {
        relativeTimeStr = "TODAY";
      } else if (difference == 1) {
        relativeTimeStr = "YESTERDAY";
      } else if (difference < 7) {
        relativeTimeStr = "${difference}D AGO";
      } else if (difference < 30) {
        final weeks = difference ~/ 7;
        relativeTimeStr = "${weeks}W AGO";
      } else if (difference < 365) {
        final months = difference ~/ 30;
        relativeTimeStr = "${months}M AGO";
      } else {
        final years = difference ~/ 365;
        relativeTimeStr = "${years}Y AGO";
      }

      String dateKey = "${DateFormat('MMM d, yyyy').format(log.dateTime)} // $relativeTimeStr";

      if (!groupedLogs.containsKey(dateKey)) {
        groupedLogs[dateKey] = [];
      }
      groupedLogs[dateKey]!.add(log);
    }

    // 3. Build Widgets
    List<Widget> widgets = [];
    groupedLogs.forEach((dateKey, logs) {
      final parts = dateKey.split(" // ");
      final dateStr = parts[0];
      final relativeStr = parts.length > 1 ? parts[1] : "";
      
      widgets.add(_buildDateHeader(dateStr, relativeStr, logs.length));
      for (var log in logs) {
        widgets.add(_buildLogItem(log));
      }
      widgets.add(const SizedBox(height: 16));
    });

    return widgets;
  }


  Widget _buildLogItem(DeviceLog log) {
    final isHighlighted = widget.highlightedLogId == log.id;
    final itemKey = isHighlighted ? widget.highlightedItemKey : null;

    return AnimatedContainer(
      key: itemKey,
      duration: const Duration(milliseconds: 500),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isHighlighted 
            ? log.iconColor.withValues(alpha: 0.15) 
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted 
              ? log.iconColor.withValues(alpha: 0.8) 
              : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          width: isHighlighted ? 2.0 : 1.0,
        ),
        boxShadow: isHighlighted ? [
          BoxShadow(
            color: log.iconColor.withValues(alpha: 0.4),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03),
            blurRadius: Theme.of(context).brightness == Brightness.dark ? 10 : 20,
            offset: Offset(0, Theme.of(context).brightness == Brightness.dark ? 4 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _showLogDetailsModal(context, log),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left color indicator strip
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: log.iconColor,
                    boxShadow: [
                      BoxShadow(
                        color: log.iconColor.withValues(alpha: isHighlighted ? 0.8 : 0.4),
                        blurRadius: isHighlighted ? 8 : 4,
                        spreadRadius: isHighlighted ? 2 : 1,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 16, bottom: 16, right: 16),
                    child: Row(
                      children: [
                        // Sensor Icon
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: log.iconColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(log.icon, color: log.iconColor, size: 24),
                        ),
                        const SizedBox(width: 16),
                        // Text Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      log.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildSmallStatusBadge(log.currentStatus),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MM/dd/yy HH:mm:ss').format(log.dateTime),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                log.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Unread dot + chevron
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (log.isUnread) Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.statusSafe,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.statusSafe.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          ],
                        ),
                      ],
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

  Widget _buildSmallStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    if (status == 'Active') {
      bgColor = AppColors.statusDanger.withValues(alpha: 0.15);
      textColor = AppColors.statusDanger;
    } else if (status == 'Resolved' || status == 'Acknowledged') {
      bgColor = AppColors.statusSafe.withValues(alpha: 0.15);
      textColor = AppColors.statusSafe;
    } else {
      bgColor = AppColors.statusWarning.withValues(alpha: 0.15);
      textColor = AppColors.statusWarning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.5),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }

  void _showLogDetailsModal(BuildContext context, DeviceLog log) {
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (context) {
        return TweenAnimationBuilder(
          duration: const Duration(milliseconds: 350),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          curve: Curves.easeOutBack,
          builder: (context, double value, child) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0 * value, sigmaY: 8.0 * value),
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: log.iconColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(log.icon, color: log.iconColor, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Activity Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8))),
                                      Text(log.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, height: 1.2)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Message banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: log.iconColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: log.iconColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, color: log.iconColor, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(log.message, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, height: 1.4))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 1. Time & Status
                            _modalSection('Time & Status', Icons.schedule),
                            _modalRow('Exact Timestamp', DateFormat('MMMM dd, yyyy – HH:mm:ss').format(log.dateTime)),
                            if (log.duration != null) _modalRow('Duration', _formatDuration(log.duration!)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Current Status', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                                _buildSmallStatusBadge(log.currentStatus),
                              ],
                            ),
                            const Divider(height: 28),

                            // 2. Telemetry Snapshot
                            _modalSection('Telemetry Snapshot', Icons.speed),
                            _modalRow('Peak Reading', log.peakSensorReading ?? 'N/A'),
                            _modalRow('Threshold Limit', log.thresholdLimit ?? 'N/A'),
                            _modalRow('Power Source', log.isMainsPower ? 'Mains (Hardwired)' : 'Battery Backup'),
                            if (log.batteryPercentage != null) _modalRow('Battery Level', '${log.batteryPercentage}%'),
                            const Divider(height: 28),

                            // 3. Automated Responses
                            _modalSection('Automated System Responses', Icons.precision_manufacturing),
                            _modalRow('Relay State', log.relayTriggered == null ? 'N/A' : (log.relayTriggered! ? 'Triggered' : 'Standby'), isHighlight: log.relayTriggered == true),
                            _modalRow('Siren State', log.sirenActivated == null ? 'N/A' : (log.sirenActivated! ? 'Activated' : 'Standby'), isHighlight: log.sirenActivated == true),
                            const SizedBox(height: 6),
                            Text('Network Actions:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            if (log.networkActions.isEmpty)
                              Text('None recorded.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic, fontSize: 13))
                            else
                              ...log.networkActions.map((action) => Padding(
                                padding: const EdgeInsets.only(bottom: 4, left: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, size: 5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(action, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13))),
                                  ],
                                ),
                              )),
                            const Divider(height: 28),

                            // 4. Location Details
                            _modalSection('Location Details', Icons.location_on),
                            _modalRow('Specific Zone', log.specificZone),
                            const SizedBox(height: 12),
                            // Map placeholder
                            Container(
                              height: 130,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2)),
                              ),
                              child: Stack(
                                children: [
                                  Center(child: Icon(Icons.map_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.25))),
                                  Center(child: Text('Floorplan View\n(Map integration pending)', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold))),
                                  const Positioned(top: 36, left: 90, child: Icon(Icons.location_on, color: AppColors.statusDanger, size: 30)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modalSection(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }

  Widget _modalRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isHighlight ? AppColors.statusDanger : Theme.of(context).colorScheme.onSurface,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeviceDetailsModal(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black54,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.97),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Grab Handle ─────────────────────────────
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // ── Header ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          title.toLowerCase().contains('power') ? Icons.bolt_rounded : Icons.router_rounded,
                          color: AppColors.primaryBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.replaceAll('\n', ' '),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "4 sensors tracked",
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant, size: 22),
                        style: IconButton.styleFrom(
                          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        
                        const SizedBox(height: 24),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("LOCATION", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                                  Text(title.toLowerCase().contains('power') ? "BATTERY %" : "STATUS", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                                ],
                              ),
                              Divider(height: 32, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),

                              if (title.toLowerCase().contains('power')) ...[
                                _buildDeviceBatteryRow("Main Entrance", "87%"),
                                const SizedBox(height: 10),
                                _buildDeviceBatteryRow("Central Stairs", "20%"),
                                const SizedBox(height: 10),
                                _buildDeviceBatteryRow("Parking Entrance", "41%"),
                                const SizedBox(height: 10),
                                _buildDeviceBatteryRow("Parking Side", "N/A"),
                              ] else ...[
                                _buildDeviceStatusRow("Main Entrance", true),
                                const SizedBox(height: 10),
                                _buildDeviceStatusRow("Central Stairs", true),
                                const SizedBox(height: 10),
                                _buildDeviceStatusRow("Parking Entrance", true),
                                const SizedBox(height: 10),
                                _buildDeviceStatusRow("Parking Side", false),
                              ],
                              
                              const SizedBox(height: 32),
                              Center(
                                child: Text(
                                  "Last sync: 2026/02/24 00:20",
                                  style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 48), // Extra padding at bottom for better feel
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildDeviceStatusRow(String location, bool isConnected) {
    final statusColor = isConnected ? AppColors.statusSafe : AppColors.statusDanger;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            location,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedPulsingDot(color: statusColor, size: 6.0),
                const SizedBox(width: 8),
                Text(
                  isConnected ? "ONLINE" : "OFFLINE",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDeviceBatteryRow(String location, String batteryStr) {
    int? batteryLevel;
    if (batteryStr.endsWith('%')) {
      batteryLevel = int.tryParse(batteryStr.substring(0, batteryStr.length - 1));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    Color batteryColor;
    if (batteryLevel == null) {
      batteryColor = colorScheme.onSurfaceVariant;
    } else if (batteryLevel >= 80) {
      batteryColor = AppColors.statusSafe;
    } else if (batteryLevel >= 40) {
      batteryColor = AppColors.statusWarning;
    } else {
      batteryColor = AppColors.statusDanger;
    }

    Widget batteryIndicator;
    bool needsCharging = batteryLevel == 0 || batteryLevel == null;

    if (needsCharging) {
      batteryIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 20,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.statusDanger.withValues(alpha: 0.5), width: 1.5),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.all(2),
            child: const Center(
              child: _BlinkingLightningIcon(),
            ),
          ),
          Container(
            width: 2,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.statusDanger.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(2), bottomRight: Radius.circular(2)),
            ),
          ),
        ],
      );
    } else {
      batteryIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 20,
            decoration: BoxDecoration(
              border: Border.all(color: batteryColor.withValues(alpha: 0.5), width: 1.5),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.all(2),
            child: Stack(
              children: [
                Container(
                  width: 38 * (batteryLevel / 100).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: batteryColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Center(
                  child: Text(
                    batteryStr,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                      color: batteryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 2,
            height: 8,
            decoration: BoxDecoration(
              color: batteryColor.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(2), bottomRight: Radius.circular(2)),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            location,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),
          batteryIndicator,
        ],
      ),
    );
  }

  Widget _buildDateHeader(String date, String relative, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 12),
      child: Row(
        children: [
          // ── Date & Relative Label Capsule ──────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.3 : 0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      date,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (relative.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Container(
                          width: 1.5,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      Text(
                        relative,
                        style: const TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // ── Count Badge ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                width: 1.2,
              ),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          
          // Spacer line to fill the rest of the row
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Divider(thickness: 1, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowingStatusCard extends StatefulWidget {
  final String title;
  final int count;
  final Color color;

  const _GlowingStatusCard({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  State<_GlowingStatusCard> createState() => _GlowingStatusCardState();
}

class _GlowingStatusCardState extends State<_GlowingStatusCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 4.0, end: 12.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, // Fallback underlying color
        gradient: LinearGradient(
          colors: [
            widget.color.withValues(alpha: 0.25),
            widget.color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.8),
                      blurRadius: _glowAnimation.value,
                      spreadRadius: _glowAnimation.value / 3,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.count.toString(),
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.w900,
              fontSize: 32,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BouncingFilterButton extends StatefulWidget {
  final VoidCallback onTap;

  const _BouncingFilterButton({required this.onTap});

  @override
  State<_BouncingFilterButton> createState() => _BouncingFilterButtonState();
}

class _BouncingFilterButtonState extends State<_BouncingFilterButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 100),
       reverseDuration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
         setState(() => _isPressed = false);
         _controller.reverse();
         widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _isPressed ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt, color: Theme.of(context).colorScheme.onSurface, size: 16),
              const SizedBox(width: 6),
              Text(
                "Filter",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedBouncingDeviceCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _AnimatedBouncingDeviceCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_AnimatedBouncingDeviceCard> createState() => _AnimatedBouncingDeviceCardState();
}

class _AnimatedBouncingDeviceCardState extends State<_AnimatedBouncingDeviceCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 100),
       reverseDuration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
         setState(() => _isPressed = false);
         _controller.reverse();
         widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 135,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: _isPressed 
                ? (Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.03))
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              if (!_isPressed)
                BoxShadow(
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.02),
                  blurRadius: Theme.of(context).brightness == Brightness.dark ? 10 : 15,
                  offset: Offset(0, Theme.of(context).brightness == Brightness.dark ? 4 : 8),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: widget.iconColor, size: 24),
              const Spacer(),
              Text(
                widget.title.replaceAll('\n', ' '), 
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                "Tap to manage",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedPulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _AnimatedPulsingDot({required this.color, this.size = 8.0});

  @override
  State<_AnimatedPulsingDot> createState() => _AnimatedPulsingDotState();
}

class _AnimatedPulsingDotState extends State<_AnimatedPulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: widget.size * 0.5, end: widget.size * 1.5).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.8),
                blurRadius: _glowAnimation.value,
                spreadRadius: _glowAnimation.value / 3,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlinkingLightningIcon extends StatefulWidget {
  const _BlinkingLightningIcon({Key? key}) : super(key: key);

  @override
  State<_BlinkingLightningIcon> createState() => _BlinkingLightningIconState();
}

class _BlinkingLightningIconState extends State<_BlinkingLightningIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value,
          child: const Icon(
            Icons.bolt,
            color: Colors.red,
            size: 16,
          ),
        );
      },
    );
  }
}

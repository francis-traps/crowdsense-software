import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/user_provider.dart';
import '../../auth/services/auth_service.dart';
import '../widgets/people_counter_card.dart';
import 'users_management_screen.dart';
import '../../../../core/providers/siren_provider.dart';

import '../../../../core/widgets/custom_notification_modal.dart';
import '../../../../core/widgets/siren_active_dialog.dart';
import '../../../../core/widgets/geometric_background.dart';
import '../../../../core/widgets/page_title.dart';
import 'analytics_screen.dart';
import 'devices_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../widgets/notifications_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final List<ScrollController> _tabScrollControllers = List.generate(5, (index) => ScrollController()..addListener(_onScroll));
  bool _isScrolled = false;
  bool _isBottomNavVisible = true;
  int _currentIndex = 0;
  PageController? _pageController;
  PageController? _overridePageController;
  int _currentOverrideIndex = 0;
  bool _showNotificationsPanel = false;
  
  // --- Log State ---
  late List<DeviceLog> _deviceLogs;
  int _hazardLevel = 0; // 0 = Nominal, 1 = Caution, 2 = Critical (Mock ESP32 data)
  Timer? _heartbeatTimer;

  int get _onlineCount => _deviceData.where((d) => d['isOnline'] == true).length;
  int get _offlineCount => _deviceData.where((d) => d['isOnline'] == false).length;

  // --- User Presence State ---
  StreamSubscription? _usersSubscription;
  int _adminsOnline = 0;
  int _facilitatorsOnline = 0;

  @override
  void initState() {
    super.initState();
    _listenToDeviceStreams();
    _listenToUserPresence();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SirenProvider>().setBottomNavVisibility(true);
      }
    });

    final now = DateTime.now();
    _deviceLogs = [
      // TODAY
      DeviceLog(
        id: 'log1',
        icon: Icons.local_fire_department,
        title: "Flame Sensor - Main Entrance",
        message: "Triggered - Possible fire detected. Evacuation protocol standing by.",
        dateTime: now.subtract(const Duration(minutes: 5)),
        iconColor: AppColors.statusDanger,
        isUnread: true,
        sensorType: 'Flame',
        priority: 'High',
        currentStatus: 'Active',
        duration: const Duration(minutes: 5),
        peakSensorReading: 'Flame Detected (Digital HIGH)',
        thresholdLimit: 'Any detection = trigger',
        isMainsPower: true,
        batteryPercentage: 82,
        relayTriggered: true,
        sirenActivated: true,
        networkActions: ['SMS alert dispatched to Security Office', 'Email notification sent to admin@crowdsense.ph'],
        specificZone: 'Block A, Floor 1, Node CS-F-001',
      ),
      DeviceLog(
        id: 'log2',
        icon: Icons.thermostat,
        title: "Temp Sensor - Server Room",
        message: "High temperature detected (42°C). Cooling system engaged automatically.",
        dateTime: now.subtract(const Duration(minutes: 20)),
        iconColor: AppColors.statusDanger,
        isUnread: true,
        sensorType: 'Temp',
        priority: 'High',
        currentStatus: 'Acknowledged',
        duration: const Duration(minutes: 20),
        peakSensorReading: '42°C',
        thresholdLimit: '38°C (critical)',
        isMainsPower: true,
        batteryPercentage: 91,
        relayTriggered: false,
        sirenActivated: false,
        networkActions: ['SMS alert dispatched to IT Department'],
        specificZone: 'Block B, Floor 2, Node CS-T-007',
      ),
      DeviceLog(
        id: 'log3',
        icon: Icons.smoking_rooms,
        title: "Smoke Sensor - Hallway A",
        message: "Smoke detected in proximity. Investigating false positive potential.",
        dateTime: now.subtract(const Duration(minutes: 45)),
        iconColor: AppColors.statusWarning,
        isUnread: false,
        sensorType: 'Smoke',
        priority: 'Mid',
        currentStatus: 'Resolved',
        duration: const Duration(minutes: 12),
        peakSensorReading: '410 ppm (analog)',
        thresholdLimit: '300 ppm threshold',
        isMainsPower: false,
        batteryPercentage: 54,
        relayTriggered: false,
        sirenActivated: false,
        networkActions: [],
        specificZone: 'Block A, Floor 3, Node CS-S-003',
      ),
      DeviceLog(
        id: 'log4',
        icon: Icons.radar,
        title: "ToF - Parking Entrance",
        message: "Device offline - Connection lost to gateway. Attempting automated reboot.",
        dateTime: now.subtract(const Duration(hours: 2, minutes: 15)),
        iconColor: AppColors.statusWarning,
        isUnread: false,
        sensorType: 'ToF',
        priority: 'Mid',
        currentStatus: 'Active',
        peakSensorReading: 'N/A (Offline)',
        thresholdLimit: 'N/A',
        isMainsPower: false,
        batteryPercentage: 18,
        networkActions: ['Automated reboot command sent'],
        specificZone: 'Parking Level 1, Node CS-P-002',
      ),
      DeviceLog(
        id: 'log5',
        icon: Icons.radar,
        title: "ToF - Main Entrance 1",
        message: "Crowd density threshold exceeded. 120 pax / min entering.",
        dateTime: now.subtract(const Duration(hours: 5)),
        iconColor: Colors.cyanAccent,
        isUnread: false,
        sensorType: 'ToF',
        priority: 'High',
        currentStatus: 'Resolved',
        duration: const Duration(minutes: 38),
        peakSensorReading: '120 pax/min',
        thresholdLimit: '80 pax/min',
        isMainsPower: true,
        batteryPercentage: 95,
        networkActions: ['SMS alert dispatched to Security Office'],
        specificZone: 'Main Gate, Floor 1, Node CS-C-001',
      ),
    ];



    _overridePageController = PageController(viewportFraction: 0.68);

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          _syncDeviceDataList();
        });
        _checkHourlyResets();
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _prototypeUnitsSubscription?.cancel();
    _sensorDataSubscription?.cancel();
    _usersSubscription?.cancel();
    _pageController?.dispose();
    _overridePageController?.dispose();
    for (var controller in _tabScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final currentController = _tabScrollControllers[_currentIndex];
    if (!currentController.hasClients) return;

    if (currentController.offset > 50 && !_isScrolled) {
      setState(() => _isScrolled = true);
    } else if (currentController.offset <= 50 && _isScrolled) {
      setState(() => _isScrolled = false);
    }

    if (currentController.position.userScrollDirection == ScrollDirection.reverse) {
      if (_isBottomNavVisible) {
        setState(() => _isBottomNavVisible = false);
        context.read<SirenProvider>().setBottomNavVisibility(false);
      }
    } else if (currentController.position.userScrollDirection == ScrollDirection.forward) {
      if (!_isBottomNavVisible) {
        setState(() => _isBottomNavVisible = true);
        context.read<SirenProvider>().setBottomNavVisibility(true);
      }
    }
  }

  Widget _buildTabScrollWrapper({required int index, required Widget child}) {
    return SingleChildScrollView(
      controller: _tabScrollControllers[index],
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + kToolbarHeight + 10,
            20,
            index == 2 ? 0 : 100),
        child: child,
      ),
    );
  }

  // Derived computed properties
  List<AppNotification> get _notifications {
    return _deviceLogs.where((log) => log.isUnread || log.currentStatus == 'Active' || log.currentStatus == 'Acknowledged').map((log) {
      final isUrgent = log.priority == 'High';
      return AppNotification(
        id: log.id,
        title: log.title,
        body: log.message,
        icon: log.icon,
        iconColor: log.iconColor,
        time: log.dateTime,
        isUrgent: isUrgent,
        isRead: !log.isUnread,
        isResolved: log.currentStatus == 'Resolved',
      );
    }).toList();
  }

  bool get _hasUrgentNotification =>
      _notifications.any((n) => n.isUrgent && !n.isResolved);

  bool get _hasAnyNotification =>
      _notifications.any((n) => (!n.isUrgent && !n.isRead) || (n.isUrgent && !n.isResolved));

  void _markAsRead(String id) {
    setState(() {
      final index = _deviceLogs.indexWhere((log) => log.id == id);
      if (index != -1) {
        _deviceLogs[index].isUnread = false;
      }
    });
  }

  void _resolveUrgent(String id) {
    setState(() {
      final index = _deviceLogs.indexWhere((log) => log.id == id);
      if (index != -1) {
        _deviceLogs[index].currentStatus = 'Resolved';
      }
    });
  }

  void _handleNotificationTap(String id) {
    _markAsRead(id);
    _resolveUrgent(id);

    setState(() {
      _currentIndex = 3; // Navigate to Devices tab
      _showNotificationsPanel = false;
      _highlightedLogId = id;
      _highlightedItemKey = GlobalKey(); // Fresh key each tap
    });

    // Give the UI a brief moment to render the newly selected tab
    // and measure the layouts before attempting to scroll.
    Future.delayed(const Duration(milliseconds: 150), () {
      final keyContext = _highlightedItemKey?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.5, // 0.5 = dead center
        );
      }
    });

    // Clear highlight after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (_highlightedLogId == id) {
            _highlightedLogId = null;
          }
        });
      }
    });
  }

  String? _highlightedLogId;
  GlobalKey? _highlightedItemKey;

  // --- Device data ---
  final Map<String, Map<String, dynamic>> _deviceDataMap = {};
  List<Map<String, dynamic>> _deviceData = [];
  String _selectedLocation = "";
  StreamSubscription? _prototypeUnitsSubscription;
  StreamSubscription? _sensorDataSubscription;

  void _listenToDeviceStreams() {
    final dbRef = FirebaseDatabase.instance.ref();
    
    _prototypeUnitsSubscription = dbRef.child('prototype_units').onValue.listen((event) {
      if (event.snapshot.value is Map) {
         final map = event.snapshot.value as Map;
         setState(() {
            map.forEach((key, val) {
               final mac = key.toString();
               final data = val as Map;
               _deviceDataMap.putIfAbsent(mac, () => {});
               _deviceDataMap[mac]!['location'] = data['name']?.toString() ?? 'Unknown';
               
               int priority = 999;
               if (data.containsKey('priority')) {
                   priority = data['priority'] is int ? data['priority'] : int.tryParse(data['priority'].toString()) ?? 999;
               } else if (data.containsKey('config') && data['config'] is Map && data['config'].containsKey('priority')) {
                   final c = data['config'] as Map;
                   priority = c['priority'] is int ? c['priority'] : int.tryParse(c['priority'].toString()) ?? 999;
               }
               _deviceDataMap[mac]!['priority'] = priority;
               
               if (data.containsKey('heartbeat') && data['heartbeat'] is Map) {
                   final hbMap = data['heartbeat'] as Map;
                   _deviceDataMap[mac]!['last_seen'] = hbMap['last_seen'];
               } else {
                   _deviceDataMap[mac]!['last_seen'] = null;
               }
            });
            _syncDeviceDataList();
         });
      } else {
        setState(() {
          _deviceDataMap.clear();
          _syncDeviceDataList();
        });
      }
    });

    _sensorDataSubscription = dbRef.child('sensor_data').onValue.listen((event) {
      if (event.snapshot.value is Map) {
         final map = event.snapshot.value as Map;
         setState(() {
            map.forEach((key, val) {
               final mac = key.toString();
               final data = val as Map;
               _deviceDataMap.putIfAbsent(mac, () => {});
               _deviceDataMap[mac]!['mac'] = mac;
               _deviceDataMap[mac]!['count'] = data['people_inside'] ?? 0;
               _deviceDataMap[mac]!['entries'] = data['total_entries'] ?? 0;
               _deviceDataMap[mac]!['exits'] = data['total_exits'] ?? 0;
               _deviceDataMap[mac]!['last_updated'] = data['last_updated'];
               _deviceDataMap[mac]!['last_reset_hour'] = data['last_reset_hour'];
            });
            _syncDeviceDataList();
         });
      }
    });
  }


  void _listenToUserPresence() {
    final dbRef = FirebaseDatabase.instance.ref();
    _usersSubscription = dbRef.child('users').onValue.listen((event) {
      if (event.snapshot.value is Map) {
        final Map<dynamic, dynamic> usersMap = event.snapshot.value as Map<dynamic, dynamic>;
        int admins = 0;
        int facilitators = 0;

        usersMap.forEach((key, value) {
          if (value is Map) {
            final bool isOnline = value['isOnline'] == true || value['isOnline'] == 1;
            final String role = (value['role']?.toString() ?? '').toLowerCase();

            if (isOnline) {
              if (role == 'admin') {
                admins++;
              } else if (role == 'facilitator') {
                facilitators++;
              }
            }
          }
        });

        if (mounted) {
          setState(() {
            _adminsOnline = admins;
            _facilitatorsOnline = facilitators;
          });
        }
      } else {
        // Handle null or invalid data
        if (mounted) {
          setState(() {
            _adminsOnline = 0;
            _facilitatorsOnline = 0;
          });
        }
      }
    });
  }


  void _syncDeviceDataList() {
    _deviceData = _deviceDataMap.values.map((v) {
        String connState = v['connection_state']?.toString() ?? "NEVER SEEN";
        bool isLive = false;

        if (connState == "CONNECTED") {
            isLive = true;
        } else if (connState == "DISCONNECTED") {
            isLive = false;
        } else {
            // Fallback for older firmware without explicit connection_state
            final lastSeen = v['last_seen'];
            if (lastSeen != null) {
                final ts = DateTime.fromMillisecondsSinceEpoch((lastSeen is int) ? lastSeen : (lastSeen as num).toInt());
                isLive = DateTime.now().difference(ts).inSeconds < 60;
                connState = isLive ? "CONNECTED" : "DISCONNECTED";
            }
        }

        return {
           'location': v['location'] ?? 'Unknown Node',
           'mac': v['mac'] ?? '',
           'count': v['count'] ?? 0,
           'entries': v['entries'] ?? 0,
           'exits': v['exits'] ?? 0,
           'isOnline': isLive,
           'connectionState': connState,
           'last_updated': v['last_updated'],
           'last_reset_hour': v['last_reset_hour'],
           'priority': v['priority'] ?? 999,
        };
    }).toList();
    
    _deviceData.sort((a, b) {
       final pA = a['priority'] as int;
       final pB = b['priority'] as int;
       return pA.compareTo(pB);
    });
    
    if (_deviceData.isNotEmpty && _selectedLocation.isEmpty) {
       _selectedLocation = _deviceData.first['location'];
    }

    if (_deviceData.isNotEmpty && _pageController == null) {
       final int realIndex = _deviceData.indexWhere((data) => data['location'] == _selectedLocation);
       _pageController = PageController(
         initialPage: 1000 * _deviceData.length + (realIndex != -1 ? realIndex : 0),
       );
    }
  }

  // --- Automated Hourly Reset Logic ---
  bool _isResettingCounts = false;

  void _checkHourlyResets() async {
    if (_isResettingCounts) return;
    final currentHour = DateTime.now().hour;
    final dbRef = FirebaseDatabase.instance.ref();
    
    for (final device in _deviceData) {
      final bool isOnline = device['isOnline'] == true;
      if (!isOnline) continue;

      final mac = device['mac']?.toString() ?? '';
      if (mac.isEmpty) continue;

      final lastResetHour = (device['last_reset_hour'] as num?)?.toInt();
      if (lastResetHour == currentHour) continue;

      // This device is online and hasn't been reset this hour yet
      _isResettingCounts = true;
      try {
        await dbRef.child('sensor_data').child(mac).update({
          'total_entries': 0,
          'total_exits': 0,
          'people_inside': 0,
          'last_reset_hour': currentHour,
        });
      } catch (_) {
        // Silently handle write failures
      }
      _isResettingCounts = false;
    }
  }

  Future<void> _resetSingleDevice(String mac, String location) async {
    final dbRef = FirebaseDatabase.instance.ref();
    final currentHour = DateTime.now().hour;
    try {
      await dbRef.child('sensor_data').child(mac).update({
        'total_entries': 0,
        'total_exits': 0,
        'people_inside': 0,
        'last_reset_hour': currentHour,
      });
      if (mounted) {
        CustomNotificationModal.show(
          context: context,
          title: "Count Reset",
          message: "Counts for '$location' have been reset to 0.",
          isSuccess: true,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotificationModal.show(
          context: context,
          title: "Reset Failed",
          message: "Could not reset counts for '$location'.",
          isSuccess: false,
        );
      }
    }
  }

  // Computed total across all sensors
  int get _totalEntries => _deviceData.fold(0, (sum, d) => sum + ((d['entries'] as num?)?.toInt() ?? 0));
  int get _totalExits => _deviceData.fold(0, (sum, d) => sum + ((d['exits'] as num?)?.toInt() ?? 0));
  int get _totalPeopleInside => (_totalEntries - _totalExits).clamp(0, 99999);

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider>();
    
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/crowdsense_logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                "CrowdSense",
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: _isScrolled
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.8)
            : Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: _isScrolled
            ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),
              )
            : null,
        titleTextStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withValues(alpha: 0.05) 
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Notification Bell ---
                  IconButton(
                    icon: Badge(
                      isLabelVisible: _hasAnyNotification,
                      smallSize: 9,
                      backgroundColor: _hasUrgentNotification
                          ? AppColors.statusDanger
                          : AppColors.statusWarning,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          key: ValueKey(_hasUrgentNotification),
                          _hasUrgentNotification
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          color: _hasUrgentNotification
                              ? AppColors.statusDanger
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _showNotificationsPanel = !_showNotificationsPanel;
                      });
                    },
                  ),
                  const SizedBox(width: 2),
                  PopupMenuButton<String>(
                    offset: const Offset(0, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    icon: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      child: Icon(Icons.person,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    onSelected: (value) async {
                      if (value == 'account') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileScreen()),
                        );
                      } else if (value == 'settings') {
                        setState(() => _currentIndex = 4);
                      } else if (value == 'logout') {
                        showDialog(
                          context: context,
                          builder: (BuildContext dialogContext) {
                            return AlertDialog(
                              title: const Text("Log Out"),
                              content: const Text("Log out of your account?"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.of(dialogContext).pop();
                                    await AuthService().logout();
                                    if (context.mounted) {
                                      context.read<UserProvider>().clearUser();
                                      Navigator.pushNamedAndRemoveUntil(
                                        context,
                                        '/login',
                                        (route) => false,
                                      );
                                    }
                                  },
                                  child: const Text(
                                    "Log Out",
                                    style: TextStyle(color: AppColors.statusDanger),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        enabled: false,
                        padding: EdgeInsets.zero,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 12),
                            CircleAvatar(
                              radius: 22,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              child: Icon(Icons.person,
                                  size: 26,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Welcome, ${userProv.firstName}!',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Divider(
                                height: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.2)),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'account',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurface),
                            const SizedBox(width: 12),
                            Text('Profile Details',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface)),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'logout',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20, color: AppColors.statusDanger),
                            SizedBox(width: 12),
                            Text('Logout',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.statusDanger,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // --- Main body ---
          GeometricBackground(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // Index 0: Dashboard Content
                _buildTabScrollWrapper(
                  index: 0,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageTitle(
                          key: ValueKey('Page_$_currentIndex'), 
                          title: "Dashboard",
                          subtitle: "Welcome, ${userProv.firstName}!",
                        ),
                        const SizedBox(height: 12),
                        _buildStatsRow(),
                        const SizedBox(height: 12),
                        _deviceData.isEmpty 
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withValues(alpha: 0.05) 
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    Icon(Icons.sensors_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(height: 16),
                                    Text("No Devices Connected", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                    const SizedBox(height: 8),
                                    Text("Add your ESP32 prototype units\nin the Device Management tab to see live data.", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ]
                              ),
                            )
                          : Builder(builder: (context) {
                          final int realIndex = _deviceData.indexWhere(
                              (data) => data['location'] == _selectedLocation);
                          return PeopleCounterCard(
                            deviceData: _deviceData,
                            currentIndex: realIndex != -1 ? realIndex : 0,
                            pageController: _pageController!,
                            onPageChanged: (index) {
                              setState(() {
                                _selectedLocation =
                                    _deviceData[index % _deviceData.length]['location'];
                              });
                            },
                            onPrevious: () {
                              _pageController!.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            onNext: () {
                              _pageController!.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          );
                        }),
                        const SizedBox(height: 12),
                        _buildCrowdCountList(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildRoleCard(context, "Admins Online", _adminsOnline, Icons.admin_panel_settings, AppColors.statusDanger)), // Red
                            const SizedBox(width: 12),
                            Expanded(child: _buildRoleCard(context, "Facilitators Online", _facilitatorsOnline, Icons.support_agent, AppColors.statusWarning)), // Orange
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildShowUsersButton(context),
                      ],
                    ),
                ),
                // Index 1: Analytics
                _buildTabScrollWrapper(
                  index: 1,
                  child: AnalyticsScreen(activeIndex: _currentIndex),
                ),
                // Index 2 (Center): Alerts & Manual Siren Control
                _buildTabScrollWrapper(
                  index: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageTitle(
                        key: ValueKey('Page_$_currentIndex'), 
                        title: "Override Siren"
                      ),
                      const SizedBox(height: 16),
                      // Tactical command strip console
                      _buildSirenCommandStrip(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "EMERGENCY OVERRIDES",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                "MANUAL SIREN CONTROL CONSOLE",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildCircularOverrideCarousel(),
                    ],
                  ),
                ),
                _buildTabScrollWrapper(
                  index: 3,
                  child: DevicesScreen(
                    logs: _deviceLogs,
                    highlightedLogId: _highlightedLogId,
                    highlightedItemKey: _highlightedItemKey,
                    parentScrollController: _tabScrollControllers[3],
                    onlineCount: _onlineCount,
                    offlineCount: _offlineCount,
                    activeIndex: _currentIndex,
                  ),
                ),
                // Index 4: Settings
                _buildTabScrollWrapper(
                  index: 4,
                  child: SettingsScreen(activeIndex: _currentIndex),
                ),
              ],
            ),
          ),

          // --- Notification Panel Overlay ---
          if (_showNotificationsPanel)
            Positioned.fill(
              top: 0,
              child: NotificationsPanel(
                notifications: _notifications,
                onClose: () => setState(() => _showNotificationsPanel = false),
                onMarkAsRead: (id) {
                  _markAsRead(id);
                  // Auto-close if no more standard notifications
                  final remaining = _notifications
                      .where((n) => !n.isUrgent && !n.isRead)
                      .length;
                  if (remaining == 0 && !_hasUrgentNotification) {
                    setState(() => _showNotificationsPanel = false);
                  }
                },
                onNotificationTap: _handleNotificationTap,
                onResolveUrgent: (id) => _resolveUrgent(id),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // The actual Navigation Bar
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: _isBottomNavVisible ? Offset.zero : const Offset(0, 1.5),
            child: Container(
              height: 90,
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: _currentIndex == 2 ? 1.0 : 0.0, end: _currentIndex == 2 ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return CustomPaint(
                    size: Size(MediaQuery.of(context).size.width - 32, 90),
                    painter: _AnimatedNavBarPainter(context, value),
                  );
                },
              ),
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(icon: Icons.home_outlined, label: "Dashboard", index: 0),
                    _buildNavItem(icon: Icons.analytics_outlined, label: "Analytics", index: 1),
                    SizedBox(
                      width: 80, 
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const SizedBox(height: 50),
                          const SizedBox(height: 10),
                          // Integrated Active Indicator for Alerts
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _currentIndex == 2 ? 1.0 : 0.0,
                            child: AnimatedScale(
                              scale: _currentIndex == 2 ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                width: 20,
                                height: 2.5,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: AppColors.primaryBlue,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryBlue.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildNavItem(icon: Icons.devices_other, label: "Devices", index: 3),
                    _buildNavItem(icon: Icons.settings_outlined, label: "Settings", index: 4),
                  ],
                ),
              ),
              Positioned(
                top: -10,
                left: MediaQuery.of(context).size.width / 2 - 16 - 32, // Parent is margin 16 left -> Center visually
                child: GestureDetector(
                  onTap: () {
                    setState(() { _currentIndex = 2; _showNotificationsPanel = false; });
                  },
                    child: AnimatedScale(
                      scale: _currentIndex == 2 ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        width: 70, // Slightly larger
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.accentBlue.withValues(alpha: 0.9),
                              AppColors.primaryBlue,
                              const Color(0xFF2563EB), // Darker shade of primaryBlue
                            ],
                            center: const Alignment(0, -0.2),
                            radius: 1.0,
                          ),
                          boxShadow: [
                            // Main shadow
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(alpha: _currentIndex == 2 ? 0.6 : 0.4),
                              blurRadius: _currentIndex == 2 ? 24 : 14,
                              offset: const Offset(0, 6),
                              spreadRadius: _currentIndex == 2 ? 2 : 0,
                            ),
                            // Bloom glow (Animated smoothly via AnimatedContainer)
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(alpha: _currentIndex == 2 ? 0.35 : 0.0),
                              blurRadius: _currentIndex == 2 ? 40 : 20,
                              spreadRadius: _currentIndex == 2 ? 8 : 0,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({required IconData icon, required String label, required int index}) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.primaryBlue : Colors.grey.withValues(alpha: 0.9);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
            _showNotificationsPanel = false;
          });
        },
        behavior: HitTestBehavior.translucent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            AnimatedScale(
              scale: isSelected ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(icon, color: color, size: 24), // Slightly smaller icons for better balance
            ),
            const SizedBox(height: 16),
            // Integrated Active Indicator
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: isSelected ? 1.0 : 0.0,
              child: AnimatedScale(
                scale: isSelected ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 20,
                  height: 2.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.primaryBlue,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color hazardColor;
    IconData hazardIcon;
    String hazardLabel;
    bool isPulsing = false;

    // Simulated dynamic hazard logic dependent on ESP32 Firebase inputs
    switch (_hazardLevel) {
      case 2:
        hazardColor = const Color(0xFFFF5252);
        hazardIcon = Icons.error_outline;
        hazardLabel = "CRITICAL ALERT";
        isPulsing = true;
        break;
      case 1:
        hazardColor = Colors.amber;
        hazardIcon = Icons.warning_amber;
        hazardLabel = "CAUTION";
        break;
      case 0:
      default:
        hazardColor = const Color(0xFF00B0FF);
        hazardIcon = Icons.health_and_safety;
        hazardLabel = "SYSTEM NORMAL";
        break;
    }

    // Styled system-notification badge for the Hazard card
    final hazardBadge = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), // Reduced padding
          decoration: BoxDecoration(
            color: hazardColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hazardColor.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start, // Align dot to the top of multi-line text
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2), // Nudge dot down slightly for alignment
                child: _PulsingDot(color: hazardColor),
              ),
              const SizedBox(width: 4), 
              Flexible(
                child: Text(
                  hazardLabel,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: hazardColor,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                  maxLines: 2, // Allow 2 lines
                  overflow: TextOverflow.ellipsis,
                  softWrap: true, // Enable wrapping
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "SYS ALERT",
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: hazardColor.withValues(alpha: 0.55),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );

    // ── Card 1: Headcount value widget ──────────────────────────────────────
    const headcountColor = Color(0xFF00C853);
    final headcountBadge = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _totalPeopleInside.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'REAL-TIME SYNC',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: headcountColor,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );

    // ── Card 2: Exits value widget ────────────────────────────────────────
    const exitsColor = Color(0xFFFF5252);
    final exitsBadge = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _totalExits.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'RESETS HOURLY',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: exitsColor,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildGlassStatCard(
              title: "Live Total\nHeadcount",
              value: '',
              icon: Icons.groups,
              color: headcountColor,
              isDark: isDark,
              valueWidget: headcountBadge,
            ),
          ),
          const SizedBox(width: 6), // Reduced from 8
          Expanded(
            child: _buildGlassStatCard(
              title: "Current Hour\nExits",
              value: '',
              icon: Icons.directions_run,
              color: exitsColor,
              isDark: isDark,
              valueWidget: exitsBadge,
            ),
          ),
          const SizedBox(width: 6), // Reduced from 8
          Expanded(
            child: _buildGlassStatCard(
              title: "Hazard Status",
              value: '',
              icon: hazardIcon,
              color: hazardColor,
              isDark: isDark,
              isPulsing: isPulsing,
              valueWidget: hazardBadge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSirenCommandStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color hazardColor;
    String hazardLabel;
    bool isPulsing = false;

    switch (_hazardLevel) {
      case 2:
        hazardColor = AppColors.statusDanger;
        hazardLabel = "CRITICAL ALERT";
        isPulsing = true;
        break;
      case 1:
        hazardColor = AppColors.statusWarning;
        hazardLabel = "CAUTION";
        break;
      default:
        hazardColor = AppColors.primaryBlue;
        hazardLabel = "SYSTEM NORMAL";
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          height: 90,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              // Zone 1: Vital Population
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _PulsingDot(color: AppColors.primaryBlue),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "LIVE POPULATION",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _totalPeopleInside.toString(),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Zone 2: Status Bay
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "HAZARD STATUS",
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSirenStatusCapsule(hazardLabel, hazardColor, isPulsing),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSirenStatusCapsule(String label, Color color, bool pulsing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          if (pulsing)
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing) ...[
            _PulsingDot(color: color),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    bool isPulsing = false,
    bool isTextSmall = false,
    Widget? valueWidget,
  }) {
    final bool isNarrow = MediaQuery.of(context).size.width < 400;
    Widget cardChild = Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 6 : 10, 
        vertical: isNarrow ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.3 : 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          // Use the custom valueWidget (e.g. badge) if provided, else plain text
          valueWidget ?? Text(
            value,
            style: TextStyle(
              fontSize: isTextSmall ? 13 : 24,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final glassWrapper = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: cardChild,
      ),
    );

    if (isPulsing) {
      return _PulsingWrapper(color: color, child: glassWrapper);
    }
    return glassWrapper;
  }

  Widget _buildCompactStat({required IconData icon, required int value, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTallyStatChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularOverrideCarousel() {
    final List<Map<String, dynamic>> overrides = [
      {
        'title': "EVACUATION SIREN",
        'subtitle': "Trigger all building sirens immediately",
        'icon': Icons.campaign_rounded,
        'color': AppColors.statusDanger,
        'isReset': false,
      },
      {
        'title': "SAFETY ALERT",
        'subtitle': "Activate blue visual strobe for advisory signalling",
        'icon': Icons.light_mode_rounded,
        'color': AppColors.primaryBlue,
        'isReset': false,
      },
      {
        'title': "RESET ALL ALARMS",
        'subtitle': "Cancel all active sirens and visual alerts",
        'icon': Icons.refresh_rounded,
        'color': AppColors.statusSafe,
        'isReset': true,
      },
    ];

    return Column(
      children: [
        SizedBox(
          height: 450,
          child: PageView.builder(
            controller: _overridePageController,
            onPageChanged: (index) => setState(() => _currentOverrideIndex = index),
            itemCount: overrides.length,
            clipBehavior: Clip.none,
            itemBuilder: (context, index) {
              final item = overrides[index];
              final isSelected = _currentOverrideIndex == index;
              
              return AnimatedScale(
                scale: isSelected ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: _TacticalDialButton(
                  title: item['title'],
                  subtitle: item['subtitle'],
                  icon: item['icon'],
                  color: item['color'],
                  isReset: item['isReset'],
                  isSelected: isSelected,
                  onTapNavigate: () {
                    _overridePageController?.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  onTrigger: () {
                    if (!mounted) return;
                    
                    // If this siren is already active, skip confirmation and show control dialog
                    final sirenProvider = context.read<SirenProvider>();
                    if (sirenProvider.activeSirenTitle == item['title'] && !item['isReset']) {
                      SirenActiveDialog.show(context, sirenProvider);
                      return;
                    }

                    const actionText = "ACTIVATE";
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return AlertDialog(
                          backgroundColor: isDark ? const Color(0xFF1E2433) : Colors.white,
                          elevation: 20,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: item['color'].withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          title: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: item['color'].withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.security_rounded, color: item['color'], size: 32),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "COMMAND AUTHORIZATION",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900, 
                                  fontSize: 18, 
                                  letterSpacing: 2.0,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "SECURITY PROTOCOL REQUIRED",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: item['color'],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Are you sure you want to $actionText the\n'${item['title']}'?\n\nThis command will be logged and executed immediately across all active zones.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14, 
                                  height: 1.5,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          actionsAlignment: MainAxisAlignment.center,
                          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          actions: [
                            (() {
                              bool isHovered = false;
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  return MouseRegion(
                                    onEnter: (_) => setState(() => isHovered = true),
                                    onExit: (_) => setState(() => isHovered = false),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: isHovered 
                                            ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)) 
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isHovered 
                                              ? (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2))
                                              : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                                          width: 1,
                                        ),
                                      ),
                                      child: TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          overlayColor: isDark ? Colors.white10 : Colors.black12,
                                        ),
                                        child: Text(
                                          "ABORT", 
                                          style: TextStyle(
                                            color: isHovered 
                                                ? (isDark ? Colors.white70 : Colors.black87)
                                                : (isDark ? Colors.white38 : Colors.grey[600]), 
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            })(),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                if (!item['isReset']) {
                                  context.read<SirenProvider>().activateSiren(item['title'], item['icon'], item['color']);
                                  SirenActiveDialog.show(context, context.read<SirenProvider>());
                                } else {
                                  context.read<SirenProvider>().terminateSiren();
                                  CustomNotificationModal.show(
                                    context: context,
                                    title: "SYSTEM RESET",
                                    message: "${item['title']} has been successfully DEACTIVATED.",
                                    isSuccess: true,
                                    customColor: item['color'],
                                    customIcon: item['icon'],
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: item['color'],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                elevation: 8,
                                shadowColor: item['color'].withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                actionText, 
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900, 
                                  letterSpacing: 1.5,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(overrides.length, (index) {
            final isSelected = _currentOverrideIndex == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              width: isSelected ? 20 : 8,
              decoration: BoxDecoration(
                color: isSelected 
                    ? overrides[index]['color'] 
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCrowdCountList() {
    if (_deviceData.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "CROWD MONITORING",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => _showCrowdCountDetail(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
                      ),
                      child: Icon(Icons.north_east_rounded,
                          color: colorScheme.onSurfaceVariant, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text("LOCATION",
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                  ),
                  Expanded(
                    child: Text("ENTRY",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                  ),
                  Expanded(
                    child: Text("EXIT",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06), height: 1),
              const SizedBox(height: 12),
              ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _deviceData.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final data = _deviceData[index];
                  final int entries = ((data['entries'] ?? 0) as num).toInt();
                  final int exits = ((data['exits'] ?? 0) as num).toInt();
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(data['location'],
                            style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      Expanded(
                        child: Text(entries.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            )),
                      ),
                      Expanded(
                        child: Text(exits.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            )),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCrowdCountDetail() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final nextReset = DateTime(now.year, now.month, now.day, now.hour + 1);
    final minsUntilReset = nextReset.difference(now).inMinutes;

    // Check if any device is online (reset is only active when devices are online)
    final bool anyOnline = _deviceData.any((d) => d['isOnline'] == true);

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (dialogContext) {
        return TweenAnimationBuilder(
          duration: const Duration(milliseconds: 350),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          curve: Curves.easeOutBack,
          builder: (context, double animValue, child) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0 * animValue, sigmaY: 8.0 * animValue),
              child: Opacity(
                opacity: animValue.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.85 + (0.15 * animValue),
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.78,
                        maxWidth: 500,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.97),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.groups_rounded, color: AppColors.primaryBlue, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Crowd Count Details",
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${_deviceData.length} sensor${_deviceData.length == 1 ? '' : 's'} registered",
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
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant, size: 22),
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ── Auto-Reset Timer Banner ─────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: anyOnline
                                      ? [AppColors.statusWarning.withValues(alpha: 0.10), AppColors.statusWarning.withValues(alpha: 0.04)]
                                      : [colorScheme.onSurfaceVariant.withValues(alpha: 0.06), colorScheme.onSurfaceVariant.withValues(alpha: 0.02)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: anyOnline
                                      ? AppColors.statusWarning.withValues(alpha: 0.25)
                                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: (anyOnline ? AppColors.statusWarning : colorScheme.onSurfaceVariant).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.timer_outlined,
                                      color: anyOnline ? AppColors.statusWarning : colorScheme.onSurfaceVariant,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          anyOnline
                                              ? "Next auto-reset in ${minsUntilReset}m"
                                              : "Auto-reset paused",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: anyOnline ? AppColors.statusWarning : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          anyOnline
                                              ? "Counts reset at the top of every hour"
                                              : "No devices online — reset will resume on connection",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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

                          const SizedBox(height: 8),

                          // ── Column Headers ──────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text("LOCATION", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.0, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text("ENTRY", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.0, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text("EXIT", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.0, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                                ),
                                const SizedBox(width: 36), // Space for reset button
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06), height: 20),
                          ),

                          // ── Device Rows ─────────────────────────
                          Flexible(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              shrinkWrap: true,
                              itemCount: _deviceData.length,
                              itemBuilder: (context, index) {
                                final data = _deviceData[index];
                                final int rawEntries = ((data['entries'] ?? 0) as num).toInt();
                                final int rawExits = ((data['exits'] ?? 0) as num).toInt();
                                final bool isOnline = data['isOnline'] == true;
                                final String mac = data['mac']?.toString() ?? '';
                                final String location = data['location']?.toString() ?? 'Unknown';

                                String updatedText = "\u2014";
                                final lu = data['last_updated'];
                                if (lu != null) {
                                  final ts = DateTime.fromMillisecondsSinceEpoch((lu is int) ? lu : (lu as num).toInt());
                                  final diff = now.difference(ts);
                                  if (diff.inSeconds < 60) {
                                    updatedText = "Just now";
                                  } else if (diff.inMinutes < 60) {
                                    updatedText = "${diff.inMinutes}m ago";
                                  } else if (diff.inHours < 24) {
                                    updatedText = "${diff.inHours}h ago";
                                  } else {
                                    updatedText = "${diff.inDays}d ago";
                                  }
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // Main data row
                                        Row(
                                          children: [
                                            // Location + Status
                                            Expanded(
                                              flex: 5,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    location,
                                                    style: TextStyle(
                                                      color: colorScheme.onSurface,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        width: 6,
                                                        height: 6,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: isOnline ? AppColors.statusSafe : AppColors.statusDanger,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: (isOnline ? AppColors.statusSafe : AppColors.statusDanger).withValues(alpha: 0.5),
                                                              blurRadius: 4,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        isOnline ? "Online" : "Offline",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                          color: isOnline ? AppColors.statusSafe : AppColors.statusDanger,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        "· $updatedText",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Entry count
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                children: [
                                                  Text(
                                                    rawEntries.toString(),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: AppColors.statusSafe,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Exit count
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                children: [
                                                  Text(
                                                    rawExits.toString(),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: AppColors.statusDanger,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Per-location reset button
                                            SizedBox(
                                              width: 36,
                                              child: IconButton(
                                                onPressed: mac.isEmpty ? null : () {
                                                  showDialog(
                                                    context: dialogContext,
                                                    barrierDismissible: true,
                                                    builder: (ctx) => AlertDialog(
                                                      backgroundColor: colorScheme.surface,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                      title: Row(
                                                        children: [
                                                          Icon(Icons.restart_alt_rounded, color: AppColors.statusWarning, size: 24),
                                                          const SizedBox(width: 10),
                                                          Expanded(
                                                            child: Text("Reset $location?", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                                                          ),
                                                        ],
                                                      ),
                                                      content: Text(
                                                        "This will reset entries, exits, and people inside to 0 for '$location'.\n\nThis action cannot be undone.",
                                                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14, height: 1.5),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx),
                                                          child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            Navigator.pop(ctx);
                                                            Navigator.pop(dialogContext);
                                                            _resetSingleDevice(mac, location);
                                                          },
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: AppColors.statusWarning,
                                                            foregroundColor: Colors.white,
                                                            elevation: 0,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                          ),
                                                          child: const Text("RESET", style: TextStyle(fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.restart_alt_rounded,
                                                  size: 18,
                                                  color: AppColors.statusWarning,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // ── Reset All Button ────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: dialogContext,
                                    barrierDismissible: true,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: colorScheme.surface,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      title: Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: AppColors.statusDanger, size: 28),
                                          const SizedBox(width: 12),
                                          const Text("Reset All Counts", style: TextStyle(fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      content: Text(
                                        "This will reset entries, exits, and people inside to 0 for ALL devices.\n\nThis action cannot be undone.",
                                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14, height: 1.5),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            Navigator.pop(dialogContext);
                                            final dbRef = FirebaseDatabase.instance.ref();
                                            final currentHour = DateTime.now().hour;
                                            for (final device in _deviceData) {
                                              final mac = device['mac']?.toString() ?? '';
                                              if (mac.isNotEmpty) {
                                                await dbRef.child('sensor_data').child(mac).update({
                                                  'total_entries': 0,
                                                  'total_exits': 0,
                                                  'people_inside': 0,
                                                  'last_reset_hour': currentHour,
                                                });
                                              }
                                            }
                                            if (mounted) {
                                              CustomNotificationModal.show(
                                                context: this.context,
                                                title: "Counts Reset",
                                                message: "All ToF counts have been reset to 0.",
                                                isSuccess: true,
                                              );
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.statusDanger,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text("RESET ALL", style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                                label: const Text("Reset All ToF Counts", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.statusDanger.withValues(alpha: 0.08),
                                  foregroundColor: AppColors.statusDanger,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: AppColors.statusDanger.withValues(alpha: 0.2)),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildRoleCard(BuildContext context, String label, int count, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: 0.15),
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
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label.toUpperCase().split(' ').first, // Just the role name
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  _PulsingDot(color: color),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "$count",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "ONLINE",
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: color.withValues(alpha: 0.7),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShowUsersButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UsersManagementScreen()),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.manage_accounts_rounded, color: AppColors.primaryBlue, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "USER RECORDS",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Manage Active Roles",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.primaryBlue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TacticalDialButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isReset;
  final bool isSelected;
  final VoidCallback onTrigger;
  final VoidCallback onTapNavigate;

  const _TacticalDialButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isReset,
    required this.isSelected,
    required this.onTrigger,
    required this.onTapNavigate,
  });

  @override
  State<_TacticalDialButton> createState() => _TacticalDialButtonState();
}

class _TacticalDialButtonState extends State<_TacticalDialButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.contain,
          child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () async {
            if (widget.isSelected) {
              // Forced 'long-press' animation sequence on tap
              setState(() => _isPressed = true);
              await Future.delayed(const Duration(milliseconds: 150));
              if (mounted) setState(() => _isPressed = false);
              widget.onTrigger();
            } else {
              widget.onTapNavigate();
            }
          },
          child: AnimatedScale(
            scale: _isPressed ? 0.94 : (widget.isSelected ? 1.0 : 0.8),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: widget.isSelected ? (0.3 + (_isPressed ? 0.2 : 0)) : 0.05),
                    blurRadius: _isPressed ? 70 : 50,
                    spreadRadius: _isPressed ? 12 : 8,
                  ),
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.5) : widget.color.withValues(alpha: 0.1),
                    offset: Offset(_isPressed ? 6 : 14, _isPressed ? 6 : 14),
                    blurRadius: _isPressed ? 15 : 28,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Ring
                  Container(
                    width: 330,
                    height: 330,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                          (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                          (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border.all(
                        color: widget.isSelected 
                            ? widget.color.withValues(alpha: 0.6) 
                            : (isDark ? Colors.white10 : Colors.black12),
                        width: 3.5,
                      ),
                      boxShadow: [
                        if (widget.isSelected)
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.3),
                            blurRadius: 25,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                  ),
                  // Machined Inner Border / Rim
                  Container(
                    width: 298,
                    height: 298,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isDark ? Colors.white24 : Colors.black12),
                        width: 1.0,
                      ),
                    ),
                  ),
                  // Inner Button Surface
                  Container(
                    width: 290,
                    height: 290,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E2433) : Colors.white,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark 
                          ? [
                              _isPressed ? const Color(0xFF161B26) : const Color(0xFF242C3D), 
                              _isPressed ? const Color(0xFF0F121A) : const Color(0xFF161B26)
                            ]
                          : [Colors.white, const Color(0xFFE2E8F0)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isPressed ? 0.4 : 0.3),
                          offset: Offset(_isPressed ? 2 : 6, _isPressed ? 2 : 6),
                          blurRadius: _isPressed ? 5 : 15,
                        ),
                        if (widget.isSelected)
                          BoxShadow(
                            color: widget.color.withValues(alpha: _isPressed ? 0.7 : 0.5),
                            blurRadius: _isPressed ? 50 : 40,
                            spreadRadius: _isPressed ? 10 : 5,
                          ),
                        // Subtle inner glow
                        BoxShadow(
                          color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.4),
                          offset: const Offset(-2, -2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.icon,
                          size: 84,
                          color: widget.isSelected ? widget.color : (isDark ? Colors.white24 : Colors.grey[400]),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: widget.isSelected ? widget.color : (isDark ? Colors.white24 : Colors.grey[400]),
                            letterSpacing: 1.0,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isSelected 
                                ? (isDark ? Colors.white.withValues(alpha: 0.75) : widget.color.withValues(alpha: 0.9))
                                : (isDark ? Colors.white10 : Colors.grey[300]),
                            letterSpacing: 0.2,
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
    ],
  );
}
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _anim.value),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedNavBarPainter extends CustomPainter {
  final BuildContext context;
  final double alertsAnimationValue;
  _AnimatedNavBarPainter(this.context, this.alertsAnimationValue);

  @override
  void paint(Canvas canvas, Size size) {
    // Safely get properties to avoid Null type errors during hot reload transitions
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final paint = Paint()
      ..color = isDark ? AppColors.surfaceDark : Colors.white
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    final path = Path();
    final double w = size.width;
    final double h = size.height;

    // Rim Light Paint
    final rimLightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, 20))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final double center = w / 2;
    
    // Notch dimensions - smoothly expands when Alerts is active
    final double notchRadius = 38.0 + (6.0 * alertsAnimationValue);
    final double notchDepth = 30.0 + (6.0 * alertsAnimationValue);

    path.moveTo(0, 24); // Top left radius
    path.quadraticBezierTo(0, 0, 24, 0);

    // Left line to notch
    path.lineTo(center - notchRadius - 15, 0);
    
    // Notch curve (Bezier that mimics a concave well)
    path.cubicTo(
      center - notchRadius + 5, 0, 
      center - notchRadius + 8, notchDepth, 
      center, notchDepth,
    );
    path.cubicTo(
      center + notchRadius - 8, notchDepth, 
      center + notchRadius - 5, 0, 
      center + notchRadius + 15, 0,
    );

    // Right line & top right radius
    path.lineTo(w - 24, 0);
    path.quadraticBezierTo(w, 0, w, 24);

    // Bottom right radius
    path.lineTo(w, h - 24);
    path.quadraticBezierTo(w, h, w - 24, h);

    // Bottom left radius
    path.lineTo(24, h);
    path.quadraticBezierTo(0, h, 0, h - 24);
    path.close();

    // Draw shadow then shape
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);

    // Tactical Machined Rim for the entire dock
    canvas.drawPath(
      path,
      Paint()
        ..color = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Subtle Rim Light on the top edge
    canvas.drawPath(path, rimLightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! _AnimatedNavBarPainter) return true;
    try {
      return oldDelegate.alertsAnimationValue != alertsAnimationValue;
    } catch (_) {
      return true;
    }
  }
}

class _PulsingWrapper extends StatefulWidget {
  final Widget child;
  final Color color;
  const _PulsingWrapper({required this.child, required this.color});

  @override
  State<_PulsingWrapper> createState() => _PulsingWrapperState();
}

class _PulsingWrapperState extends State<_PulsingWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _anim.value * 0.4),
                blurRadius: 16 * _anim.value,
                spreadRadius: 2 * _anim.value,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

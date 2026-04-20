import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_notification_modal.dart';

class DeviceManagementModal extends StatefulWidget {
  const DeviceManagementModal({super.key});

  @override
  State<DeviceManagementModal> createState() => _DeviceManagementModalState();
}

class _DeviceManagementModalState extends State<DeviceManagementModal> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription? _devicesSubscription;
  List<Map<String, dynamic>> _devices = [];

  final TextEditingController _macController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    _listenToDevices();
  }

  void _listenToDevices() {
    _devicesSubscription = _dbRef.child('prototype_units').onValue.listen((event) {
      if (event.snapshot.value != null && event.snapshot.value is Map) {
        final Map<dynamic, dynamic> devicesMap = event.snapshot.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> loadedDevices = [];
        
        devicesMap.forEach((key, value) {
          if (value is Map) {
            final device = <String, dynamic>{};
            value.forEach((k, v) => device[k.toString()] = v);
            device['macAddress'] = key.toString();
            
            if (!device.containsKey('sensors') && device.containsKey('config') && device['config'] is Map) {
               final configMap = device['config'] as Map;
               final sensorsStrMap = <String, dynamic>{};
               configMap.forEach((k, v) => sensorsStrMap[k.toString()] = v);
               device['sensors'] = sensorsStrMap;
            } else if (!device.containsKey('sensors')) {
               device['sensors'] = <String, dynamic>{
                  "temp_threshold": 35.0,
                  "smoke_threshold": 300.0,
                  "flame_threshold": 200.0
               };
            }

            // No longer fetching manual 'status' field as Operation Power is removed.
            // Heartbeat data below will handle the LIVE/OFFLINE state.

            // Extract heartbeat data
            if (device.containsKey('heartbeat') && device['heartbeat'] is Map) {
              final hbMap = device['heartbeat'] as Map;
              device['heartbeat_status'] = hbMap['connection_state']?.toString() ?? 'NEVER SEEN';
              device['heartbeat_last_seen'] = hbMap['last_seen'];
              device['heartbeat_ip'] = hbMap['ip_address']?.toString();
              device['heartbeat_firmware'] = hbMap['firmware_version']?.toString();
            } else {
              device['heartbeat_status'] = 'NEVER SEEN';
              device['heartbeat_last_seen'] = null;
            }

            loadedDevices.add(device);
          }
        });

        // Sort by priority if available
        loadedDevices.sort((a, b) {
          final pA = a['priority'] ?? 999;
          final pB = b['priority'] ?? 999;
          return pA.compareTo(pB);
        });

        if (mounted) {
          setState(() {
            _devices = loadedDevices;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _devices = [];
          });
        }
      }
    }, onError: (error) {
      debugPrint("Error listening to devices stream: $error");
    });
  }

  void _addDeviceToFirebase(String mac, String name) async {
    try {
      await _dbRef.child('prototype_units').child(mac).set({
        "name": name,
        "priority": _devices.length,
        "config": {
          "temp_threshold": 35.0,
          "smoke_threshold": 300.0,
          "flame_threshold": 200.0,
          "priority": _devices.length,
        }
      });
      // Pre-initialize sensor data logic
      await _dbRef.child('sensor_data').child(mac).set({
        "people_inside": 0,
        "total_entries": 0,
        "total_exits": 0,
        "temperature": 0.0,
        "gas": 0,
        "flame": 0,
        "last_updated": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint("Error adding device: $e");
    }
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    
    setState(() {
      final device = _devices.removeAt(oldIndex);
      _devices.insert(newIndex, device);
    });

    // Batch update priorities in Firebase
    for (int i = 0; i < _devices.length; i++) {
        _dbRef.child('prototype_units').child(_devices[i]['macAddress']).update({
            'priority': i,
        });
    }
  }


  // Removed _updateDeviceStatus as manual power control is no longer supported.

  void _removeDeviceFromFirebase(String mac) async {
    try {
      await _dbRef.child('prototype_units').child(mac).remove();
      await _dbRef.child('sensor_data').child(mac).remove();
    } catch (e) {
      debugPrint("Error removing device: $e");
    }
  }

  void _handleAddDevice() {
    if (_macController.text.trim().isEmpty || _nameController.text.trim().isEmpty) {
      CustomNotificationModal.show(
        context: context,
        title: "Missing Fields",
        message: "Please fill in both MAC Address and Node Name.",
        isSuccess: false,
      );
      return;
    }

    final String mac = _macController.text.trim();
    final String name = _nameController.text.trim();

    _addDeviceToFirebase(mac, name);

    _macController.clear();
    _nameController.clear();

    FocusScope.of(context).unfocus();
    
    CustomNotificationModal.show(
      context: context,
      title: "Device Added",
      message: "Device '$name' has been added successfully.",
      isSuccess: true,
    );
  }

  void _promptRemoveDevice(String mac, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.statusDanger, size: 28),
              const SizedBox(width: 12),
              const Text("Remove Device", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text("Are you sure you want to permanently remove '$name'?\n\nThis will disconnect the hardware node and stop incoming sensor data."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _executeRemoveDevice(mac, name);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusDanger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _executeRemoveDevice(String mac, String name) {
    _removeDeviceFromFirebase(mac);
    
    CustomNotificationModal.show(
      context: context,
      title: "Device Removed",
      message: "Device '$name' has been permanently removed.",
      isSuccess: true,
      isDestructive: true,
    );
  }

  void _executeEditDevice(String oldMac, String newMac, String newName, Map<String, dynamic> newSensors) async {
    try {
      if (oldMac == newMac) {
        await _dbRef.child('prototype_units').child(oldMac).update({
          "name": newName,
          "config": newSensors,
        });
      } else {
        final protoSnapshot = await _dbRef.child('prototype_units').child(oldMac).get();
        final sensorSnapshot = await _dbRef.child('sensor_data').child(oldMac).get();

        if (protoSnapshot.exists) {
           final baseData = Map<String, dynamic>.from(protoSnapshot.value as Map);
           baseData["name"] = newName;
           baseData["config"] = newSensors;
           await _dbRef.child('prototype_units').child(newMac).set(baseData);
        }

        if (sensorSnapshot.exists) {
           await _dbRef.child('sensor_data').child(newMac).set(sensorSnapshot.value);
        }

        await _dbRef.child('prototype_units').child(oldMac).remove();
        await _dbRef.child('sensor_data').child(oldMac).remove();
      }

      if (mounted) {
        CustomNotificationModal.show(
          context: context,
          title: "Device Updated",
          message: "Device settings have been successfully saved.",
          isSuccess: true,
        );
      }
    } catch (e) {
      debugPrint("Error editing device: $e");
    }
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _macController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.97),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
              blurRadius: 30,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: Column(
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
            
            _buildHeader(context),
            
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle("ADD NEW DEVICE"),
                    const SizedBox(height: 16),
                    _buildAddDeviceForm(isDark),
                    
                    const SizedBox(height: 32),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle("CONFIGURED DEVICES"),
                        if (_devices.length > 1)
                          IconButton(
                            icon: Icon(
                              _isReordering ? Icons.check_circle_rounded : Icons.reorder_rounded,
                              color: _isReordering ? AppColors.statusSafe : AppColors.primaryBlue,
                              size: 22,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: (_isReordering ? AppColors.statusSafe : AppColors.primaryBlue).withValues(alpha: 0.12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => setState(() => _isReordering = !_isReordering),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDeviceList(isDark),
                    
                    const SizedBox(height: 64), // Extra padding at bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.settings_suggest_rounded,
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
                  "Device Management",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Manage sensor nodes",
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
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildAddDeviceForm(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _macController,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: "MAC ADDRESS",
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)),
              hintText: "e.g. 00:1B:44:11:3A:B7",
              prefixIcon: Icon(Icons.memory_rounded, color: AppColors.primaryBlue.withValues(alpha: 0.7), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: "LOCATION/NODE NAME",
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)),
              hintText: "e.g. CEA 3rd Floor",
              prefixIcon: Icon(Icons.location_on_rounded, color: AppColors.primaryBlue.withValues(alpha: 0.7), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleAddDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 20),
                  SizedBox(width: 8),
                  Text("Add Device", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(bool isDark) {
    if (_devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(Icons.devices_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                "No devices configured yet.",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (_isReordering) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return Padding(
            key: ValueKey(device["macAddress"]),
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _EditableDeviceTile(
              key: ValueKey(device["macAddress"]),
              device: device,
              isDark: isDark,
              isReordering: _isReordering,
              index: index,
              onSave: _executeEditDevice,
              onRemove: _promptRemoveDevice,
              onStatusToggle: (mac, status) {}, // No-op
            ),
          );
        },
        onReorder: _handleReorder,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _devices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final device = _devices[index];
        // One-time cleanup: Remove 'status' field from RTDB if it exists
        if (device.containsKey('status')) {
           FirebaseDatabase.instance.ref().child('prototype_units').child(device['macAddress']).child('status').remove();
        }
        return _buildDeviceTile(device, isDark, index: index);
      },
    );
  }

  Widget _buildDeviceTile(Map<String, dynamic> device, bool isDark, {int index = 0}) {
    return _EditableDeviceTile(
      key: ValueKey(device["macAddress"]),
      device: device,
      isDark: isDark,
      isReordering: _isReordering,
      index: index,
      onSave: _executeEditDevice,
      onRemove: _promptRemoveDevice,
      onStatusToggle: (mac, status) {
        // No-op as Operation Power is removed. Cleanup happens in _buildDeviceList.
      },
    );
  }
}

class _EditableDeviceTile extends StatefulWidget {
  final Map<String, dynamic> device;
  final bool isDark;
  final bool isReordering;
  final int index;
  final Function(String, String, String, Map<String, dynamic>) onSave;
  final Function(String, String) onRemove;
  final Function(String, String) onStatusToggle;

  const _EditableDeviceTile({
    super.key,
    required this.device,
    required this.isDark,
    this.isReordering = false,
    this.index = 0,
    required this.onSave,
    required this.onRemove,
    required this.onStatusToggle,
  });

  @override
  State<_EditableDeviceTile> createState() => _EditableDeviceTileState();
}

class _EditableDeviceTileState extends State<_EditableDeviceTile> {
  late TextEditingController _macCtrl;
  late TextEditingController _nameCtrl;
  late double _tempThresh;
  Timer? _heartbeatTimer;
  late double _smokeThresh;
  late double _flameThresh;

  @override
  void initState() {
    super.initState();
    _macCtrl = TextEditingController(text: widget.device["macAddress"]);
    _nameCtrl = TextEditingController(text: widget.device["name"]);
    final sensors = widget.device["sensors"] as Map<String, dynamic>;
    _tempThresh = (sensors["temp_threshold"] ?? 35.0).toDouble();
    _smokeThresh = (sensors["smoke_threshold"] ?? 300.0).toDouble();
    _flameThresh = (sensors["flame_threshold"] ?? 200.0).toDouble();

    // Refresh the "ago" text every 10 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _macCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // --- Heartbeat helpers ---
  String get _hardwareState {
    final hwStatus = widget.device['heartbeat_status']?.toString() ?? 'NEVER SEEN';
    if (hwStatus == 'CONNECTED' || hwStatus == 'DISCONNECTED') {
        return hwStatus;
    }
    
    final lastSeen = widget.device['heartbeat_last_seen'];
    if (lastSeen != null) {
        final ts = DateTime.fromMillisecondsSinceEpoch((lastSeen is int) ? lastSeen : (lastSeen as num).toInt());
        return DateTime.now().difference(ts).inSeconds < 60 ? 'CONNECTED' : 'DISCONNECTED';
    }
    return 'NEVER SEEN';
  }

  bool get _isHardwareLive {
    return _hardwareState == 'CONNECTED';
  }

  String get _lastSeenText {
    final lastSeen = widget.device['heartbeat_last_seen'];
    if (lastSeen == null) return 'Never connected';
    final ts = DateTime.fromMillisecondsSinceEpoch((lastSeen is int) ? lastSeen : (lastSeen as num).toInt());
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bool isLive = _isHardwareLive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isLive ? AppColors.primaryBlue : AppColors.textGrey).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.router_rounded,
              color: isLive ? AppColors.primaryBlue : AppColors.textGrey,
              size: 22,
            ),
          ),
          title: Text(
            widget.device["name"],
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          trailing: widget.isReordering 
            ? ReorderableDragStartListener(
                index: widget.index,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(Icons.drag_handle_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isLive ? AppColors.statusSafe : AppColors.textGrey).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isLive ? AppColors.statusSafe : AppColors.textGrey).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedPulsingDot(
                      color: isLive ? AppColors.statusSafe : AppColors.textGrey,
                      size: 6,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: isLive ? AppColors.statusSafe : AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
          children: widget.isReordering ? [] : [
            const SizedBox(height: 8),
            _buildHeartbeatCard(),
            const SizedBox(height: 16),
            
            // Edit Fields
            Text("DEVICE DETAILS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
            const SizedBox(height: 12),
            TextField(
              controller: _macCtrl,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: "MAC Address",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                filled: true,
                fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: "Location Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                filled: true,
                fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
                isDense: true,
              ),
            ),
            
            const SizedBox(height: 24),
            Text("SENSOR THRESHOLDS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            
            _buildThresholdSlider("Temperature", _tempThresh, 30, 60, AppColors.statusDanger, "°C", (v) => setState(() => _tempThresh = v)),
            _buildThresholdSlider("Smoke", _smokeThresh, 100, 500, AppColors.primaryBlue, "PPM", (v) => setState(() => _smokeThresh = v)),
            _buildThresholdSlider("Flame", _flameThresh, 50, 500, AppColors.statusWarning, "PPM", (v) => setState(() => _flameThresh = v)),
            
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onSave(
                         widget.device["macAddress"], 
                         _macCtrl.text.trim(), 
                         _nameCtrl.text.trim(), 
                         {
                            "temp_threshold": _tempThresh,
                            "smoke_threshold": _smokeThresh,
                            "flame_threshold": _flameThresh,
                         }
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => widget.onRemove(widget.device["macAddress"], widget.device["name"]),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.statusDanger.withValues(alpha: 0.4), width: 1.5),
                      foregroundColor: AppColors.statusDanger,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Remove", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdSlider(String label, double value, double min, double max, Color color, String unit, Function(double) onChange) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text("${value.toStringAsFixed(label == 'Temperature' ? 1 : 0)} $unit", style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: color,
            inactiveColor: color.withValues(alpha: 0.1),
            onChanged: onChange,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHeartbeatCard() {
    final hwState = _hardwareState;
    final ip = widget.device['heartbeat_ip'];
    final firmware = widget.device['heartbeat_firmware'];
    final isLive = hwState == 'CONNECTED';
    final color = isLive ? AppColors.statusSafe : (hwState == 'DISCONNECTED' ? AppColors.statusDanger : AppColors.textGrey);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLive ? Icons.sensors : Icons.sensors_off,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                "ESP32 Hardware",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hwState.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _heartbeatDetail(Icons.access_time, 'Last Seen', _lastSeenText),
              if (ip != null) ...[const SizedBox(width: 16), _heartbeatDetail(Icons.lan, 'IP', ip)],
              if (firmware != null) ...[const SizedBox(width: 16), _heartbeatDetail(Icons.memory, 'FW', firmware)],
            ],
          ),
        ],
      ),
    );
  }

  Widget _heartbeatDetail(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
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
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.6 * _animation.value),
                blurRadius: widget.size * _animation.value,
                spreadRadius: (widget.size / 2) * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

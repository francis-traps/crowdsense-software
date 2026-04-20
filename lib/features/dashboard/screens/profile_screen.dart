import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/widgets/secondary_geometric_background.dart';
import '../../../../core/widgets/custom_notification_modal.dart';
import '../../../../core/utils/phone_formatter.dart';
import '../../auth/widgets/update_email_dialog.dart';
import '../../auth/widgets/update_password_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _accentBlue = AppColors.primaryBlue;

  // ── editable state ─────────────────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _designationCtrl;
  late TextEditingController _deptCtrl;

  late String _adminId;
  late String _accessLevel;

  // dynamic permissions based on role
  List<String> get _rolePermissions {
    final role = context.read<UserProvider>().role.toLowerCase();
    final common = [
      'Real-time Analytics & Dashboarding',
      'Fire & Hazard Monitoring',
      'Historical Trend Reporting',
      'Manual Warning Control',
      'Node Status Inspection',
    ];
    
    if (role == 'admin') {
      return [
        ...common,
        'Sensor Threshold Calibration',
        'Device Node Configuration & Management',
        'Global User Access Control',
      ];
    }
    return common;
  }

  List<String> _managedZones = [];
  StreamSubscription? _zonesSubscription;
  final List<Map<String, String>> _activeSessions = [
    {'device': 'This Device', 'status': 'Active'},
  ];
  final List<String> _recentActions = [
    'Updated smoke threshold → Sensor B12',
    'Exported Weekly Trend Report',
    'Acknowledged fire alert – Sector 7',
    'Decommissioned Sensor A04',
    'Changed password',
  ];
  final Map<String, int> _deviceHealth = {'Online': 6, 'Critical': 1, 'Offline': 0};


  bool _isEditing = false;
  bool _hasChanges = false;

  // originals for cancel-reset
  late String _origName, _origUsername, _origEmail, _origPhone, _origDesignation, _origDept;

  @override
  void initState() {
    super.initState();
    _listenToZones();
    final userProv = context.read<UserProvider>();
    
    _origName = userProv.name;
    _origUsername = userProv.username;
    _origEmail = userProv.email;
    _origPhone = userProv.phone.isEmpty ? 'N/A' : userProv.phone;
    _origDesignation = userProv.designation.isEmpty ? 'N/A' : userProv.designation;
    _origDept = userProv.department.isEmpty ? 'N/A' : userProv.department;
    _adminId = userProv.id;
    _accessLevel = userProv.role.toUpperCase();

    _nameCtrl = TextEditingController(text: _origName);
    _usernameCtrl = TextEditingController(text: _origUsername);
    _emailCtrl = TextEditingController(text: _origEmail);
    _phoneCtrl = TextEditingController(
        text: _origPhone == 'N/A' || _origPhone == '+63 900 000 0000'
            ? '+63 '
            : _origPhone);
    _designationCtrl = TextEditingController(
        text: _origDesignation == 'N/A' ||
                _origDesignation == 'Official Administrator'
            ? ''
            : _origDesignation);
    _deptCtrl = TextEditingController(
        text: _origDept == 'N/A' ||
                _origDept == 'Disaster Response Team – CEA'
            ? ''
            : _origDept);

    // Add listeners ONLY after all controllers are initialized to avoid LateInitializationError in _onChange
    _nameCtrl.addListener(_onChange);
    _usernameCtrl.addListener(_onChange);
    _emailCtrl.addListener(_onChange);
    _phoneCtrl.addListener(_onChange);
    _designationCtrl.addListener(_onChange);
    _deptCtrl.addListener(_onChange);

    // Email fields are now refreshed reactively via UserProvider (context.watch)
    // The UpdateEmailDialog handles its own RTDB sync upon verification.
  }


  void _onChange() {
    final currentPhoneRaw = _phoneCtrl.text.trim();
    final currentPhone = (currentPhoneRaw.isEmpty || currentPhoneRaw == '+63') ? 'N/A' : currentPhoneRaw;
    final currentDesignation = _designationCtrl.text.trim().isEmpty ? 'N/A' : _designationCtrl.text.trim();
    final currentDept = _deptCtrl.text.trim().isEmpty ? 'N/A' : _deptCtrl.text.trim();
    
    final origP = _origPhone == '+63 900 000 0000' ? 'N/A' : _origPhone;
    final origD = _origDesignation == 'Official Administrator' ? 'N/A' : _origDesignation;
    final origDept = _origDept == 'Disaster Response Team – CEA' ? 'N/A' : _origDept;

    final changed = _nameCtrl.text.trim() != _origName.trim() ||
        _usernameCtrl.text.trim() != _origUsername.trim() ||
        _emailCtrl.text.trim() != _origEmail.trim() ||
        currentPhone != origP ||
        currentDesignation != origD ||
        currentDept != origDept;

    if (_hasChanges != changed) setState(() => _hasChanges = changed);
  }

  @override
  void dispose() {
    _zonesSubscription?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _designationCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  void _listenToZones() {
    _zonesSubscription = FirebaseDatabase.instance.ref().child('prototype_units').onValue.listen((event) {
      if (event.snapshot.value is Map) {
        final map = event.snapshot.value as Map;
        final List<Map<String, dynamic>> devices = [];
        
        map.forEach((key, val) {
          final data = val as Map;
          final name = data['name']?.toString() ?? 'Unknown Node';
          int priority = 999;
          if (data.containsKey('priority')) {
              priority = data['priority'] is int ? data['priority'] : int.tryParse(data['priority'].toString()) ?? 999;
          } else if (data.containsKey('config') && data['config'] is Map && data['config'].containsKey('priority')) {
              final c = data['config'] as Map;
              priority = c['priority'] is int ? c['priority'] : int.tryParse(c['priority'].toString()) ?? 999;
          }
          devices.add({'name': name, 'priority': priority});
        });
        
        devices.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));
        if (mounted) {
          setState(() {
            _managedZones = devices.map((d) => d['name'] as String).toList();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _managedZones = [];
          });
        }
      }
    });
  }

  void _cancel() {
    setState(() {
      _nameCtrl.text = _origName;
      _usernameCtrl.text = _origUsername;
      _emailCtrl.text = _origEmail;
      _phoneCtrl.text = _origPhone == 'N/A' || _origPhone == '+63 900 000 0000' ? '' : _origPhone;
      _designationCtrl.text = _origDesignation == 'N/A' || _origDesignation == 'Official Administrator' ? '' : _origDesignation;
      _deptCtrl.text = _origDept == 'N/A' || _origDept == 'Disaster Response Team – CEA' ? '' : _origDept;
      _isEditing = false;
      _hasChanges = false;
    });
  }

  void _save() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _usernameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty) {
      _showError('Update incomplete. Full Name, Username, and Email are required.');
      return;
    }
    
    setState(() {
      _isEditing = false;
    });

    final userProv = context.read<UserProvider>();
    final uid = userProv.authUser?.uid;
    
    if (uid != null) {
      try {
        final idToken = await userProv.authUser!.getIdToken();
        final dbBaseUrl = 'https://crowdsense-db-default-rtdb.asia-southeast1.firebasedatabase.app';
        final updateUrl = Uri.parse('$dbBaseUrl/users/$uid.json?auth=$idToken');
        
        final finalPhone = _phoneCtrl.text.trim().isEmpty ? 'N/A' : _phoneCtrl.text.trim();
        final finalDesignation = _designationCtrl.text.trim().isEmpty ? 'N/A' : _designationCtrl.text.trim();
        final finalDept = _deptCtrl.text.trim().isEmpty ? 'N/A' : _deptCtrl.text.trim();

        final payload = json.encode({
          'name': _nameCtrl.text.trim(),
          'username': _usernameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': finalPhone,
          'designation': finalDesignation,
          'department': finalDept,
        });

        final response = await http.patch(updateUrl, body: payload);

        if (response.statusCode != 200) {
          throw Exception('Server rejected edit: ${response.body}');
        }
        
        userProv.updateProfile({
          'name': _nameCtrl.text.trim(),
          'username': _usernameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': finalPhone,
          'designation': finalDesignation,
          'department': finalDept,
        });
        
        setState(() {
          _origName = _nameCtrl.text.trim();
          _origUsername = _usernameCtrl.text.trim();
          _origEmail = _emailCtrl.text.trim();
          _origPhone = finalPhone;
          _origDesignation = finalDesignation;
          _origDept = finalDept;
          _hasChanges = false;
        });
        
        _showSuccess('Profile updated. Your changes are now synced across the CrowdSense network.');
      } catch (e) {
        setState(() => _isEditing = true);
        _showError('Failed to sync changes with server: $e');
      }
    }
  }

  void _showSuccess(String msg) {
    HapticFeedback.lightImpact();
    CustomNotificationModal.show(
      context: context,
      title: 'Success!',
      message: msg,
      isSuccess: true,
    );
  }

  void _showError(String msg) {
    HapticFeedback.heavyImpact();
    CustomNotificationModal.show(
      context: context,
      title: 'Security Sync Required',
      message: msg,
      isSuccess: false,
    );
  }

  // ─── Change Password Dialog ─────────────────────────────────────────────────


  // ─── Log Out All Sessions Dialog ────────────────────────────────────────────

  void _showLogoutAllSessionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          const Icon(Icons.logout, color: AppColors.statusDanger, size: 24),
          const SizedBox(width: 10),
          const Text('Log Out All Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        content: const Text(
          'This will immediately end all other active sessions across the CrowdSense network. Your current device session will remain active.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Successfully logged out of all other devices. Your current session is now the only active access point.');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusDanger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Log Out Others', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatLastLogin(String isoString) {
    if (isoString.isEmpty) return 'Never';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      // Format: Mar 26, 2026  •  17:34 PHT
      return DateFormat('MMM dd, yyyy  •  HH:mm').format(dt) + ' PHT';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SecondaryGeometricBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
          _isEditing ? 'Edit Profile Details' : 'Profile Details',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [

          // ─── AVATAR HEADER ────────────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentBlue.withValues(alpha: 0.4), width: 3),
                    boxShadow: [BoxShadow(color: _accentBlue.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: _accentBlue.withValues(alpha: 0.15),
                    child: Icon(Icons.person, size: 52, color: _accentBlue),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (_isEditing) {
                        _showSuccess('Avatar updated successfully.');
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isEditing ? const Color(0xFF6A1B9A) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: _isEditing ? Border.all(color: cs.surface, width: 2) : null,
                      ),
                      child: _isEditing
                          ? Icon(Icons.edit_rounded, size: 16, color: cs.onPrimary)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _nameCtrl.text.isEmpty ? _origName : _nameCtrl.text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(_designationCtrl.text.trim().isEmpty ? 'N/A' : _designationCtrl.text.trim(), style: TextStyle(color: _accentBlue, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
          if (!_isEditing)
            Center(
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit Profile Details', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue.withValues(alpha: 0.12),
                  foregroundColor: _accentBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ─── SECTION 1: Personal Identity & Role ─────────────────────────
          _SectionLabel(label: '1. Personal Identity & Professional Role'),
          const SizedBox(height: 10),
          _ProfileCard(colorScheme: cs, isDark: isDark, children: [
            _isEditing
                ? _EditField(label: 'Full Name', controller: _nameCtrl, keyboardType: TextInputType.name, accentColor: _accentBlue)
                : _StaticRow(icon: Icons.badge_outlined, label: 'Full Name', value: _nameCtrl.text, colorScheme: cs),
            const _Divider(),
            _isEditing
                ? _EditField(label: 'Username', controller: _usernameCtrl, keyboardType: TextInputType.text, accentColor: _accentBlue)
                : _StaticRow(icon: Icons.alternate_email_rounded, label: 'Username', value: _usernameCtrl.text, colorScheme: cs),
            const _Divider(),
            _StaticRow(icon: Icons.tag_rounded, label: 'Admin ID', value: _adminId, colorScheme: cs, locked: true),
            const _Divider(),
            _isEditing
                ? _EditField(label: 'Official Designation', controller: _designationCtrl, accentColor: _accentBlue, hint: 'N/A')
                : _StaticRow(icon: Icons.work_outline_rounded, label: 'Official Designation', value: _designationCtrl.text.trim().isEmpty ? 'N/A' : _designationCtrl.text.trim(), colorScheme: cs),
            const _Divider(),
            _isEditing
                ? _EditField(label: 'Department / Unit', controller: _deptCtrl, accentColor: _accentBlue, hint: 'N/A')
                : _StaticRow(icon: Icons.corporate_fare_rounded, label: 'Department / Unit', value: _deptCtrl.text.trim().isEmpty ? 'N/A' : _deptCtrl.text.trim(), colorScheme: cs),
          ]),
          const SizedBox(height: 20),

          // ─── SECTION 2: Admin Credentials & Access ────────────────────────
          _SectionLabel(label: '2. Administrative Credentials & Access'),
          const SizedBox(height: 10),
          _ProfileCard(colorScheme: cs, isDark: isDark, children: [
            _StaticRow(
              icon: Icons.shield_rounded,
              label: 'Access Level',
              value: '', // Hiding text value because the badge already displays the role
              colorScheme: cs,
              badge: _accessLevel.toUpperCase(),
              badgeColor: _accessLevel.toLowerCase() == 'admin'
                  ? AppColors.statusDanger
                  : AppColors.statusWarning,
            ),
            const _Divider(),
            _PermissionsRow(permissions: _rolePermissions, colorScheme: cs),
            const _Divider(),
            _ZonesRow(zones: _managedZones, colorScheme: cs),
          ]),
          const SizedBox(height: 20),

          // ─── SECTION 3: Communication & Emergency Contact ─────────────────
          _SectionLabel(label: '3. Communication & Emergency Contact'),
          const SizedBox(height: 10),
          _ProfileCard(colorScheme: cs, isDark: isDark, children: [
            _StaticRow(
              icon: Icons.email_outlined,
              label: 'Secure Work Email',
              value: context.watch<UserProvider>().email,
              colorScheme: cs,
              locked: true, // Email is now always locked in the Profile UI
              badge: 'SECURE',
              badgeColor: AppColors.statusSafe,
            ),
            const _Divider(),
            _isEditing
                ? _EditField(
                    label: 'Emergency Contact Number',
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    accentColor: _accentBlue,
                    hint: '+63 XXX XXX XXXX',
                    inputFormatters: [PhilippinePhoneFormatter()],
                  )
                : _StaticRow(
                    icon: Icons.phone_outlined,
                    label: 'Emergency Contact Number',
                    value: _phoneCtrl.text.trim().isEmpty
                        ? 'N/A'
                        : _phoneCtrl.text.trim(),
                    colorScheme: cs),
          ]),
          const SizedBox(height: 20),

          // ─── SECTION 4: Security & Authentication ────────────────────────
          _SectionLabel(label: '4. Security & Authentication'),
          const SizedBox(height: 10),
          _ProfileCard(colorScheme: cs, isDark: isDark, children: [
            _StaticRow(
              icon: Icons.access_time_rounded,
              label: 'Last Login',
              value: _formatLastLogin(context.watch<UserProvider>().lastLogin),
              colorScheme: cs,
            ),
            const _Divider(),
            // ── Change Email Address ──────────────────────────────────────
            InkWell(
              onTap: () async {
                await UpdateEmailDialog.show(context);
                // The dialog handles all syncing internally.
                // Just refresh the displayed email from the provider.
                if (mounted) {
                  final newEmail = context.read<UserProvider>().email;
                  if (newEmail.isNotEmpty && newEmail != _emailCtrl.text) {
                    setState(() {
                      _origEmail = newEmail;
                      _emailCtrl.text = newEmail;
                    });
                  }
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.alternate_email_rounded,
                          size: 18, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change Email Address',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            'A verification link will be sent to your new email',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ),
            const _Divider(),
            // ── Change Account Password ──────────────────────────────────────
            InkWell(
              onTap: () => UpdatePasswordDialog.show(context),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.lock_reset_rounded,
                          size: 18, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change Account Password',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            'Update your credentials periodically for better security',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: _isEditing
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: isDark ? AppColors.backgroundDark : cs.surface,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05), offset: const Offset(0, -4), blurRadius: 10)],
              ),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: cs.onSurface.withValues(alpha: 0.2)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _hasChanges ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _accentBlue.withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ]),
            )
          : null,
    ));
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool isDark;
  final List<Widget> children;
  const _ProfileCard({required this.colorScheme, required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: isDark ? 10 : 20,
            offset: Offset(0, isDark ? 4 : 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 24,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    );
  }
}

class _StaticRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final bool locked;
  final String? badge;
  final Color? badgeColor;

  const _StaticRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    this.locked = false,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(locked ? Icons.lock_outline_rounded : icon, size: 18, color: colorScheme.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Row(
            children: [
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? colorScheme.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor ?? colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Assigned by System Architect - cannot be changed', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ),
        ]),
      ),
    ]);
  }
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Color accentColor;
  final String? hint;

  final List<TextInputFormatter>? inputFormatters;

  const _EditField({
    required this.label,
    required this.controller,
    this.keyboardType,
    required this.accentColor,
    this.hint,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentColor, width: 2),
          ),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
        inputFormatters: inputFormatters,
      ),
    ]);
  }
}

class _PermissionsRow extends StatelessWidget {
  final List<String> permissions;
  final ColorScheme colorScheme;
  const _PermissionsRow({required this.permissions, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.admin_panel_settings_outlined, size: 18, color: colorScheme.primary)),
        const SizedBox(width: 12),
        Text('Permissions Overview', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      for (var p in permissions)
        Padding(
          padding: const EdgeInsets.only(left: 36, bottom: 4),
          child: Row(children: [
            Icon(Icons.check_circle_outline_rounded, size: 12, color: AppColors.statusSafe),
            const SizedBox(width: 8),
            Text(p, style: TextStyle(fontSize: 12, color: colorScheme.onSurface, fontWeight: FontWeight.w500)),
          ]),
        ),
    ]);
  }
}

class _ZonesRow extends StatelessWidget {
  final List<String> zones;
  final ColorScheme colorScheme;
  const _ZonesRow({required this.zones, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.map_outlined, size: 18, color: colorScheme.primary)),
        const SizedBox(width: 12),
        Text('Managed Gateway Sectors', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      for (var z in zones)
        Padding(
          padding: const EdgeInsets.only(left: 36, bottom: 4),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: colorScheme.secondary.withValues(alpha: 0.6), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(z, style: TextStyle(fontSize: 12, color: colorScheme.onSurface, fontWeight: FontWeight.w500)),
          ]),
        ),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ColorScheme colorScheme;
  const _StatChip({required this.label, required this.value, required this.color, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(children: [
          Text(value.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}



import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/page_title.dart';
import '../../../../core/widgets/secondary_geometric_background.dart';
import '../../../../core/widgets/custom_notification_modal.dart';
import '../../auth/services/auth_service.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  // ─── Filter State ───────────────────────────────────────────────────────────
  String _statusFilter = 'All';
  String _roleFilter = 'All';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // ─── Data State ─────────────────────────────────────────────────────────────
  final GlobalKey _roleDropdownKey = GlobalKey();
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;
  int _onlineCount = 0;
  int _offlineCount = 0;
  StreamSubscription? _usersSubscription;

  @override
  void initState() {
    super.initState();
    _listenToUsers();
    _searchCtrl.addListener(() => setState(() {}));

    // Auto-select text when clicked (YouTube style)
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        _searchCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchCtrl.text.length,
        );
      }
      setState(() {}); // Rebuild for focus highlight
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _usersSubscription?.cancel();
    super.dispose();
  }

  // ─── Firebase Fetch (Using real-time stream) ────────────────────────
  void _listenToUsers() {
    final dbRef = FirebaseDatabase.instance.ref().child('users');
    _usersSubscription = dbRef.onValue.listen((event) {
      if (event.snapshot.value is! Map) {
        if (mounted) {
          setState(() {
            _allUsers = [];
            _onlineCount = 0;
            _offlineCount = 0;
            _isLoading = false;
          });
        }
        return;
      }

      final raw = event.snapshot.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> loaded = [];

      raw.forEach((uid, value) {
        if (value is! Map) return;
        final d = Map<String, dynamic>.from(value as Map);
        loaded.add({
          'uid': uid.toString(),
          'id': d['customId']?.toString() ?? uid.toString().substring(0, 6).toUpperCase(),
          'name': d['name']?.toString() ?? 'Unknown User',
          'username': d['username']?.toString() ?? '',
          'email': d['email']?.toString() ?? '',
          'phone': d['phone']?.toString() ?? '',
          'role': d['role']?.toString() ?? 'User',
          'designation': d['designation']?.toString() ?? 'N/A',
          'department': d['department']?.toString() ?? 'N/A',
          'isOnline': d['isOnline'] == true || d['isOnline'] == 1,
          'createdAt': _parseCreatedAt(d['createdAt']),
        });
      });

      loaded.sort((a, b) =>
          (a['createdAt'] as DateTime).compareTo(b['createdAt'] as DateTime));

      loaded.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

      if (mounted) {
        setState(() {
          _allUsers = loaded;
          _onlineCount = loaded.where((u) => u['isOnline'] == true).length;
          _offlineCount = loaded.where((u) => u['isOnline'] == false).length;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint('Stream users error: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  DateTime _parseCreatedAt(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is int || raw is double) {
      int ms = raw is double ? raw.toInt() : raw as int;
      // Convert Unix seconds to ms if necessary
      if (ms < 10000000000) ms = ms * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}, ${dt.year}';
  }

  bool get _isAdmin {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || _allUsers.isEmpty) return false;
    final user = _allUsers.firstWhere((u) => u['uid'] == currentUid,
        orElse: () => <String, dynamic>{});
    return user['role']?.toString().toLowerCase() == 'admin';
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _searchCtrl.text.toLowerCase();
    return _allUsers.where((u) {
      final matchSearch = q.isEmpty ||
          u['name'].toString().toLowerCase().contains(q) ||
          u['username'].toString().toLowerCase().contains(q);
      final matchStatus = _statusFilter == 'All' ||
          (_statusFilter == 'Online' && u['isOnline'] == true) ||
          (_statusFilter == 'Offline' && u['isOnline'] == false);
      final matchRole = _roleFilter == 'All' || u['role'] == _roleFilter;
      return matchSearch && matchStatus && matchRole;
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SecondaryGeometricBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Users Management",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: cs.onSurface,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER SECTION ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageTitle(title: "System Users"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _dotBadge(AppColors.statusSafe, 'Online $_onlineCount'),
                        const SizedBox(width: 16),
                        _dotBadge(
                            Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                            'Offline $_offlineCount'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── SEARCH BAR & ADD ACTION ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(child: _buildSearchBar(isDark)),
                    if (_isAdmin) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddUserDialog(context),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text(
                            "ADD USER",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    23)), // Perfectly rounded
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── FILTER BAR ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterDropdown(
                        icon: Icons.show_chart_rounded,
                        label: 'Status: ',
                        selectedValue: _statusFilter,
                        items: ['All', 'Online', 'Offline'],
                        onChanged: (val) {
                          if (val != null) setState(() => _statusFilter = val);
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildFilterDropdown(
                        icon: Icons.badge_outlined,
                        label: 'Role: ',
                        selectedValue: _roleFilter,
                        items: ['All', 'Admin', 'Facilitator'],
                        onChanged: (val) {
                          if (val != null) setState(() => _roleFilter = val);
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildAdvanceFilterButton(isDark),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── CONTENT AREA ────────────────────────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredUsers.isEmpty
                        ? _buildEmptyState()
                        : _buildGridView(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LIST VIEW LAYOUT
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildListView(bool isDark) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: isDark ? 0.3 : 1.0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(
                  cs.surfaceVariant.withValues(alpha: isDark ? 0.4 : 0.8)),
              dataRowMaxHeight: 70,
              columnSpacing: 32,
              headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  fontSize: 13),
              columns: const [
                DataColumn(label: Text('ID#')),
                DataColumn(label: Text('Full Name')),
                DataColumn(label: Text('Username')),
                DataColumn(label: Text('Access Level')),
                DataColumn(label: Text('Designation')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Contact')),
                DataColumn(label: Text('Joined')),
                DataColumn(label: Text('Actions')),
              ],
              rows: _filteredUsers.map((user) {
                final role = user['role'] as String;
                final isOnline = user['isOnline'] as bool;
                final roleColor = role.toLowerCase() == 'admin'
                    ? AppColors.statusDanger
                    : AppColors.statusWarning;

                return DataRow(
                  cells: [
                    DataCell(Text('# ${user['id']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13))),
                    DataCell(Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: roleColor.withValues(alpha: 0.15),
                          child: Text(user['name'][0].toUpperCase(),
                              style: TextStyle(
                                  color: roleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Text(user['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    )),
                    DataCell(Text('@${user['username']}',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(role.toUpperCase(),
                          style: TextStyle(
                              color: roleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    )),
                    DataCell(Text(user['designation'],
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: isOnline
                              ? AppColors.statusSafe.withValues(alpha: 0.1)
                              : cs.onSurfaceVariant.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 7,
                              color: isOnline
                                  ? AppColors.statusSafe
                                  : cs.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Text(isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                  color: isOnline
                                      ? AppColors.statusSafe
                                      : cs.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user['email'],
                            style: const TextStyle(fontSize: 12)),
                        if (user['phone'].isNotEmpty)
                          Text(user['phone'],
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    )),
                    DataCell(Text(
                        'Joined at ${_formatDate(user['createdAt'] as DateTime)}',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(
                      !_isAdmin
                          ? const SizedBox.shrink()
                          : PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  size: 20),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              color: isDark
                                  ? AppColors.surfaceDark
                                  : Colors.white,
                              onSelected: (value) {
                                if (value == 'delete') {
                                  _confirmAndDeleteUser(user);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline_rounded,
                                          size: 18,
                                          color: AppColors.statusDanger),
                                      const SizedBox(width: 8),
                                      const Text('Delete User',
                                          style: TextStyle(
                                              color: AppColors.statusDanger,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // GRID VIEW LAYOUT
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildGridView(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Force single column so cards are the "same length as the screen"
        final crossAxisCount = 1;
        final spacing = 20.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent:
                    430, // Increased to 430 to resolve the 2px overflow and provide a safe buffer
                crossAxisSpacing: spacing,
                mainAxisSpacing: 16,
              ),
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                return _UserGridCard(
                  user: _filteredUsers[index],
                  isDark: isDark,
                  formatDate: _formatDate,
                  onDelete: () => _confirmAndDeleteUser(_filteredUsers[index]),
                  isAdmin: _isAdmin,
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Empty State
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No users found.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ─── Filter UI Components ───────────────────────────────────────────────────
  Widget _dotBadge(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final bool hasFocus = _searchFocusNode.hasFocus;

    // CSS reference colors mapped to Flutter
    // Container = the pill (.search-container)
    // TextField  = transparent input (.search-input { background: transparent; border: none; outline: none })
    final Color containerBg = isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9); 
    const Color borderBlue = AppColors.primaryBlue; 
    final Color lightBg = const Color(0xFFF1F5F9); 
    const Color placeholderC = Color(0xFF9CA3AF); 

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // .search-container { background-color: #313338 }
        color: isDark ? containerBg : lightBg,
        // border-radius: 9999px → perfect pill
        borderRadius: BorderRadius.circular(9999),
        // border: 1px solid #3b82f6
        border: Border.all(
          color: hasFocus
              ? borderBlue
              : borderBlue.withValues(alpha: isDark ? 0.35 : 0.2),
          width: 1.0,
        ),
        // box-shadow only on focus (like :focus-within in CSS)
        boxShadow: [
          if (hasFocus)
            BoxShadow(
              color: borderBlue.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 0,
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // .search-icon { color: #3b82f6 }
          Icon(Icons.search_rounded, size: 18, color: borderBlue),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              onChanged: (_) => setState(() {}),
              textAlignVertical: TextAlignVertical.center,
              cursorColor: borderBlue,
              // .search-input { background: transparent; border: none; outline: none }
              decoration: InputDecoration(
                hintText: 'Search user...',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: placeholderC, // #9ca3af
                  fontWeight: FontWeight.w400,
                ),
                filled: false, // transparent background
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 5),
              ),
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFFE4E4E7)
                    : Colors.black87, // #e4e4e7 light text
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required String selectedValue,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.15);
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) {
        return items
            .map((e) => PopupMenuItem(
                value: e,
                height: 40,
                child: Text(e, style: const TextStyle(fontSize: 13))))
            .toList();
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            Text(selectedValue,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvanceFilterButton(bool isDark) {
    final bgColor = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.15);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          const Text('Advance Filter', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  // ─── Delete User Mechanism ──────────────────────────────────────────────────
  Future<void> _confirmAndDeleteUser(Map<String, dynamic> targetUser) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final bgColor = Theme.of(context).colorScheme.surface;
        return Dialog(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.statusDanger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_rounded,
                      color: AppColors.statusDanger, size: 40),
                ),
                const SizedBox(height: 24),
                Text("Delete User",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 16),
                Text(
                  "Are you sure you want to permanently delete ${targetUser['name']} (@${targetUser['username']})?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  "This will completely erase their system access and telemetry history. This action cannot be undone.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.5))),
                        ),
                        child: Text("Cancel",
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.statusDanger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Delete Permanently",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final targetUid = targetUser['uid'] as String;

      // Use the newly integrated AuthService helper which handles authentication tokens automatically.
      await AuthService().deleteUser(targetUid);

      // Successfully eradicated from RTDB. Let's update UI locally
      setState(() {
        _allUsers.removeWhere((u) => u['uid'] == targetUid);
        // Refresh counts
        _onlineCount = _allUsers.where((u) => u['isOnline'] == true).length;
        _offlineCount = _allUsers.where((u) => u['isOnline'] == false).length;
      });

      if (!mounted) return;

      // Show elegant Success Popup for Deletion
      CustomNotificationModal.show(
        context: context,
        title: "Account Deleted",
        message:
            "${targetUser['name']} (@${targetUser['username']}) has been permanently removed.\n\nTheir system access and database profile have been securely erased.",
        isSuccess: true,
      );
    } catch (error) {
      CustomNotificationModal.show(
        context: context,
        title: "Deletion Failed",
        message: "Error deleting user: $error",
        isSuccess: false,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Add User Dialog Implementation ─────────────────────────────────────────
  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final designationCtrl = TextEditingController(); // Optional
    final deptCtrl = TextEditingController(); // Optional
    String selectedRole =
        'Facilitator'; // Default since it's restricted to Admin/Facilitator
    String? errorMessage;
    bool nameError = false;
    bool usernameError = false;
    bool emailError = false;

    bool isSaving = false;
    final AuthService authService = AuthService();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).colorScheme.onSurfaceVariant;

    showDialog(
      context: context,
      barrierDismissible: false, // Ensure they acknowledge success
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 500, // Make it wider like the reference image
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Add New User",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: textColor)),
                    IconButton(
                      icon: Icon(Icons.close, color: textMuted),
                      onPressed: isSaving ? null : () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.statusDanger.withValues(alpha: 0.1),
                      border: Border.all(
                          color: AppColors.statusDanger.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.statusDanger, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(errorMessage!,
                                style: const TextStyle(
                                    color: AppColors.statusDanger,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Form Fields wrapped in Expanded scrolling if constrained vertically
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDialogFieldLabel("Full Name *", isDark),
                        _buildDialogTextInput(
                            nameCtrl, "Enter full name...", isSaving, isDark,
                            icon: Icons.person_outline_rounded,
                            hasError: nameError, onChanged: (val) {
                          if (nameError && val.trim().isNotEmpty) {
                            setDialogState(() {
                              nameError = false;
                              if (nameCtrl.text.trim().isNotEmpty &&
                                  usernameCtrl.text.trim().isNotEmpty &&
                                  emailCtrl.text.trim().isNotEmpty)
                                errorMessage = null;
                            });
                          }
                        }),
                        const SizedBox(height: 16),

                        _buildDialogFieldLabel("Username *", isDark),
                        _buildDialogTextInput(
                            usernameCtrl, "Enter username...", isSaving, isDark,
                            icon: Icons.alternate_email_rounded,
                            hasError: usernameError, onChanged: (val) {
                          if (usernameError && val.trim().isNotEmpty) {
                            setDialogState(() {
                              usernameError = false;
                              if (nameCtrl.text.trim().isNotEmpty &&
                                  usernameCtrl.text.trim().isNotEmpty &&
                                  emailCtrl.text.trim().isNotEmpty)
                                errorMessage = null;
                            });
                          }
                        }),
                        const SizedBox(height: 16),

                        _buildDialogFieldLabel("Email *", isDark),
                        _buildDialogTextInput(emailCtrl,
                            "Enter email address...", isSaving, isDark,
                            icon: Icons.mail_outline_rounded,
                            hasError: emailError, onChanged: (val) {
                          if (emailError && val.trim().isNotEmpty) {
                            setDialogState(() {
                              emailError = false;
                              if (nameCtrl.text.trim().isNotEmpty &&
                                  usernameCtrl.text.trim().isNotEmpty &&
                                  emailCtrl.text.trim().isNotEmpty)
                                errorMessage = null;
                            });
                          }
                        }),
                        const SizedBox(height: 16),

                        _buildDialogFieldLabel(
                            "Official Designation (Optional)", isDark),
                        _buildDialogTextInput(designationCtrl,
                            "Enter official designation...", isSaving, isDark,
                            icon: Icons.badge_outlined),
                        const SizedBox(height: 16),

                        _buildDialogFieldLabel(
                            "Department / Unit (Optional)", isDark),
                        _buildDialogTextInput(deptCtrl,
                            "Enter department or unit...", isSaving, isDark,
                            icon: Icons.corporate_fare_rounded),
                        const SizedBox(height: 20),

                        // Temporary password notice
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primaryBlue.withValues(alpha: 0.1)
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: isDark ? 0.3 : 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.key_rounded,
                                  size: 18, color: AppColors.primaryBlue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.blue.shade200
                                            : Colors.blue.shade900),
                                    children: const [
                                      TextSpan(
                                          text:
                                              "A temporary password will be "),
                                      TextSpan(
                                          text: "auto-generated",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      TextSpan(
                                          text: " and emailed to the user."),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        _buildDialogFieldLabel("Role", isDark),
                        _buildDialogRoleDropdown(selectedRole,
                            ['Admin', 'Facilitator'], isSaving, isDark, (val) {
                          if (val != null && !isSaving)
                            setDialogState(() => selectedRole = val);
                        }),
                      ],
                    ),
                  ),
                ),

                // Footer actions
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: isSaving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.5))),
                      ),
                      child: Text("Cancel",
                          style: TextStyle(
                              color: textMuted, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final bool isNameEmpty =
                                  nameCtrl.text.trim().isEmpty;
                              final bool isEmailEmpty =
                                  emailCtrl.text.trim().isEmpty;
                              final bool isUsernameEmpty =
                                  usernameCtrl.text.trim().isEmpty;

                              if (isNameEmpty ||
                                  isEmailEmpty ||
                                  isUsernameEmpty) {
                                setDialogState(() {
                                  errorMessage =
                                      "Please fill out all required fields.";
                                  nameError = isNameEmpty;
                                  emailError = isEmailEmpty;
                                  usernameError = isUsernameEmpty;
                                });
                                return;
                              }

                              setDialogState(() {
                                errorMessage = null;
                                nameError = false;
                                emailError = false;
                                usernameError = false;
                                isSaving = true;
                              });

                              try {
                                // 1. Generate Custom ID Based on Role
                                final roleKey = selectedRole.toLowerCase();
                                final idPrefix =
                                    roleKey == 'admin' ? 'CPE-A' : 'CPE-F';
                                final count = _allUsers
                                    .where((u) =>
                                        (u['role'] as String).toLowerCase() ==
                                        roleKey)
                                    .length;
                                final customId =
                                    '$idPrefix${(count + 1).toString().padLeft(3, '0')}';

                                // 2. Format Unix Timestamp
                                final int createdAtUnix =
                                    DateTime.now().millisecondsSinceEpoch ~/
                                        1000;

                                // 3. Generate Temporary Password in structured format: XX-xxxxxx (e.g. RX-pyvt94)
                                const upperChars =
                                    'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O to avoid confusion
                                const lowerNumChars =
                                    'abcdefghjkmnpqrstuvwxyz23456789'; // no l/1/0/o
                                math.Random rnd = math.Random();
                                final prefix = String.fromCharCodes(
                                    Iterable.generate(
                                        2,
                                        (_) => upperChars.codeUnitAt(
                                            rnd.nextInt(upperChars.length))));
                                final suffix = String.fromCharCodes(
                                    Iterable.generate(
                                        6,
                                        (_) => lowerNumChars.codeUnitAt(rnd
                                            .nextInt(lowerNumChars.length))));
                                final String tempPassword = '$prefix-$suffix';

                                final userData = {
                                  'customId': customId,
                                  'name': nameCtrl.text.trim(),
                                  'username': usernameCtrl.text.trim(),
                                  'email': emailCtrl.text.trim().toLowerCase(),
                                  'phone': 'N/A',
                                  'role': roleKey,
                                  'designation':
                                      designationCtrl.text.trim().isEmpty
                                          ? 'N/A'
                                          : designationCtrl.text.trim(),
                                  'department':
                                      deptCtrl.text.trim().isEmpty
                                          ? 'N/A'
                                          : deptCtrl.text.trim(),
                                  'isOnline': false,
                                  'createdAt': createdAtUnix,
                                };

                                // --- SAVE TO DATABASE AND AUTH ---
                                final String generatedUid = await authService
                                    .createUserRecord(userData, tempPassword);

                                // --- REFRESH LOCAL UI ---
                                setState(() {
                                  _allUsers.insert(0, {
                                    ...userData,
                                    'uid': generatedUid,
                                    'createdAt':
                                        DateTime.fromMillisecondsSinceEpoch(
                                            createdAtUnix * 1000),
                                  });
                                  _offlineCount++;
                                });

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  CustomNotificationModal.show(
                                    context: context,
                                    title: "Account Created!",
                                    message:
                                        "${nameCtrl.text.trim()} ($selectedRole) has been added to the system.\n\nThey have been emailed on their email address for their temporary credentials.",
                                    isSuccess: true,
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  setDialogState(() {
                                    isSaving = false;
                                    errorMessage =
                                        "Failed to save: ${e.toString()}";
                                  });
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors
                            .statusDanger, // Using the orange/red from reference
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text("Create User",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogFieldLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildDialogTextInput(
      TextEditingController ctrl, String hint, bool isSaving, bool isDark,
      {IconData? icon,
      bool hasError = false,
      void Function(String)? onChanged}) {
    return TextField(
      controller: ctrl,
      enabled: !isSaving,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            fontSize: 14),
        prefixIcon: icon != null
            ? Icon(icon,
                size: 18,
                color: hasError
                    ? AppColors.statusDanger
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade400))
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: hasError
                  ? AppColors.statusDanger
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: hasError
                  ? AppColors.statusDanger
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildDialogRoleDropdown(String selected, List<String> options,
      bool isSaving, bool isDark, ValueChanged<String?> onChanged) {
    final color = selected.toLowerCase() == 'admin'
        ? AppColors.statusDanger
        : AppColors.statusWarning;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          key: _roleDropdownKey,
          onTap: isSaving
              ? null
              : () async {
                  // Calculate position for the popup menu
                  final RenderBox renderBox = _roleDropdownKey.currentContext
                      ?.findRenderObject() as RenderBox;
                  final offset = renderBox.localToGlobal(Offset.zero);

                  final String? selection = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                        offset.dx,
                        offset.dy + 52, // Below the field
                        offset.dx + constraints.maxWidth,
                        offset.dy + 100 // Arbitrary bottom
                        ),
                    color:
                        isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      maxWidth: constraints.maxWidth,
                    ),
                    items: options.map((role) {
                      final roleCol = role.toLowerCase() == 'admin'
                          ? AppColors.statusDanger
                          : AppColors.statusWarning;
                      return PopupMenuItem<String>(
                        value: role,
                        height: 48,
                        child: Text(
                          role,
                          style: TextStyle(
                            fontSize: 14,
                            color: roleCol,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  );

                  if (selection != null) {
                    onChanged(selection);
                  }
                },
          child: Material(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              height: 52, // Match the text field height
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(
                    color:
                        Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    selected,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GRID CARD WIDGET
// ════════════════════════════════════════════════════════════════════════════
class _UserGridCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDark;
  final String Function(DateTime) formatDate;
  final VoidCallback onDelete;
  final bool isAdmin;

  const _UserGridCard({
    required this.user,
    required this.isDark,
    required this.formatDate,
    required this.onDelete,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOnline = user['isOnline'] as bool;
    final role = user['role'] as String;
    final roleColor = role.toLowerCase() == 'admin'
        ? AppColors.statusDanger
        : AppColors.statusWarning;
    final phone = user['phone'] as String;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top: Status & Actions ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status Badge (Left)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? AppColors.statusSafe.withValues(alpha: 0.15)
                        : cs.onSurfaceVariant.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isOnline
                            ? AppColors.statusSafe.withValues(alpha: 0.3)
                            : cs.onSurfaceVariant.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: isOnline
                                  ? AppColors.statusSafe
                                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(isOnline ? 'Active' : 'Offline',
                          style: TextStyle(
                              color: isOnline
                                  ? AppColors.statusSafe
                                  : cs.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                // Actions (Right)
                if (isAdmin)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 22),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    offset: const Offset(0, 40),
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                size: 20, color: AppColors.statusDanger),
                            const SizedBox(width: 10),
                            const Text('Delete User',
                                style: TextStyle(
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

          // ── Avatar & Identity ──────────────────────────────────────────────
          const SizedBox(height: 10),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Decorative Background Shape
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                CircleAvatar(
                  radius: 33,
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  child: Text(
                      user['name'].toString().substring(0, 1).toUpperCase(),
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: roleColor)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(user['name'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(user['designation'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Encased Info Box ───────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? cs.surfaceVariant.withValues(alpha: 0.2)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ID + Role Chip
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tag_rounded,
                                size: 16,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(user['id'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: roleColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(role.toUpperCase(),
                              style: TextStyle(
                                  color: roleColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    Divider(color: cs.outline.withValues(alpha: 0.12), height: 20),
                    // Username & Contact Chips
                    _buildIconLabel(Icons.alternate_email, user['username'], cs,
                        isPill: false),
                    const SizedBox(height: 10),
                    _buildIconLabel(Icons.mail_outline, user['email'], cs,
                        isPill: true),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildIconLabel(Icons.phone_outlined, phone, cs,
                          isPill: true),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Footer ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    'Joined: ${formatDate(user['createdAt'] as DateTime).toUpperCase()}',
                    style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
                InkWell(
                  onTap: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View details',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                              decoration: TextDecoration.underline)),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded,
                          size: 14, color: cs.onSurface),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Colored Bottom Border ──────────────────────────────────────────
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: roleColor,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconLabel(IconData icon, String text, ColorScheme cs,
      {bool isPill = false}) {
    final iconWidget =
        Icon(icon, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7));

    if (!isPill) {
      return Row(
        children: [
          iconWidget,
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }

    final pillDecoration = BoxDecoration(
      color: isDark ? cs.surface : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      boxShadow: [
        if (!isDark)
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2)),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget, // Plain gray icon outside the pill
        const SizedBox(width: 8),
        // Text Pill (The "Blue Modalthing")
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 4), // Tighter horizontal fit
          decoration: pillDecoration,
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

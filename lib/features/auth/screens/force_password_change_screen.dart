import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/geometric_background.dart';

class ForcePasswordChangeScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;

  const ForcePasswordChangeScreen({
    super.key, 
    required this.email,
    required this.userData,
  });

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _newPasswordCtrl.addListener(() => setState(() {}));
    _confirmPasswordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // Real-time Regex Validations
  bool get _hasMinLength => _newPasswordCtrl.text.length >= 8;
  bool get _hasUpperLower => RegExp(r'(?=.*[A-Z])(?=.*[a-z])').hasMatch(_newPasswordCtrl.text);
  bool get _hasNumber => RegExp(r'\d').hasMatch(_newPasswordCtrl.text);
  bool get _hasSpecial => RegExp(r'[\!\@\#\$\%\^\&\*\.\,\?]').hasMatch(_newPasswordCtrl.text);
  bool get _passwordsMatch => _newPasswordCtrl.text.isNotEmpty && _newPasswordCtrl.text == _confirmPasswordCtrl.text;

  bool get _isValid => _hasMinLength && _hasUpperLower && _hasNumber && _hasSpecial && _passwordsMatch;

  Future<void> _submit() async {
    if (!_isValid) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Session lost. Please log in again.");

      final idToken = await user.getIdToken();
      
      // 1. Remove the 'requiresPasswordChange' flag from RTDB to allow dashboard entry (VIA REST API)
      final dbUrl = Uri.parse('https://crowdsense-db-default-rtdb.asia-southeast1.firebasedatabase.app/users/${user.uid}.json?auth=$idToken');
      final dbResponse = await http.patch(
        dbUrl,
        body: json.encode({'requiresPasswordChange': false}),
      );
      if (dbResponse.statusCode != 200) {
        throw Exception("Failed to sync status to database securely: ${dbResponse.statusCode}");
      }

      // 2. Update Firebase Authentication Password Securely (VIA REST ON WINDOWS TO PREVENT C++ PLUGIN CRASH)
      // The `firebase_auth_windows` plugin contains a severe C++ threading crash condition on `updatePassword`.
      // Bypassing the native MethodChannel entirely by using Google's raw Identity Toolkit API for updates:
      final apiKey = Firebase.app().options.apiKey;
      final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:update?key=$apiKey');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': idToken,
          'password': _newPasswordCtrl.text,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to perform secure password exchange: ${response.statusCode}");
      }
      
      if (!mounted) return;
      
      // Update the local instance payload so it matches DB
      widget.userData['requiresPasswordChange'] = false;
      
      // Ensure RTDB is online before navigating to dashboard
      // (On desktop, goOffline() was called during login for C++ SDK safety)
      FirebaseDatabase.instance.goOnline();

      // Proceed to the dashboard gracefully
      Navigator.pushReplacementNamed(
        context, 
        '/splash', 
        arguments: {
          'nextRoute': '/dashboard',
          'authFuture': Future.value(true),
        }
      );
      
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceAll(RegExp(r'\[.*?\] '), '');
      });
    }
  }

  Widget _buildCheckRow(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: met ? AppColors.statusSafe : Colors.grey.shade600,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(
              color: met ? AppColors.statusSafe : Colors.grey.shade400,
              fontSize: 13,
              fontWeight: met ? FontWeight.bold : FontWeight.normal
            )),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: GeometricBackground(
        child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 0 : 20.0),
              child: FadeInDown(
                duration: const Duration(milliseconds: 700),
                child: Container(
                  width: 500,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark, // CrowdSense Dark Theme Widget color
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon matching IPAM's shield concept
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.statusWarning.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.security_rounded, size: 36, color: AppColors.statusWarning),
                        ),
                        const SizedBox(height: 20),
                        
                        const Text(
                          "Change Your Password",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "For security purposes, you must set a new complex password before continuing.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        ),
                        const SizedBox(height: 30),

                        // Error message
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.statusDanger.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.statusDanger),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.statusDanger, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 13))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        
                        // New Password Input
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("New Password *", style: TextStyle(color: Colors.grey.shade300, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _newPasswordCtrl,
                              obscureText: _obscureNew,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.backgroundDark,
                                prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade500, size: 18),
                                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Confirm Password Input
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Confirm New Password *", style: TextStyle(color: Colors.grey.shade300, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscureConfirm,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.backgroundDark,
                                prefixIcon: Icon(
                                  Icons.check_circle_outline, 
                                  color: _passwordsMatch ? AppColors.statusSafe : Colors.grey.shade500, 
                                  size: 18
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade500, size: 18),
                                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8), 
                                  borderSide: _passwordsMatch 
                                      ? const BorderSide(color: AppColors.statusSafe, width: 1.5)
                                      : BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Password Strength Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundDark.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("PASSWORD STRENGTH", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildCheckRow("Min 8 characters", _hasMinLength),
                                        _buildCheckRow("Number (0-9)", _hasNumber),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildCheckRow("Uppercase & Lowercase", _hasUpperLower),
                                        _buildCheckRow("Special Char (!@#\$%^&*.?)", _hasSpecial),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Submission Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isValid && !_isLoading ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusDanger, // Orange/Red matching D1-IPAM submission button theme
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                              disabledBackgroundColor: Colors.grey.shade800,
                            ),
                            child: _isLoading 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Set New Password & Continue", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        const Text(
                          "Protected System. Authorized Personnel Only.",
                          style: TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

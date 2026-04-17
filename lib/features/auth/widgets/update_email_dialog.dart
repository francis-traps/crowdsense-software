import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../firebase_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/user_provider.dart';

/// A three-step email update dialog:
///   Step 1 — Re-authenticate (current password)
///   Step 2 — Enter new email
///   Step 3 — Success confirmation
///
/// Usage: `await UpdateEmailDialog.show(context);`
class UpdateEmailDialog {
  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _UpdateEmailDialogWidget(),
    );
  }
}

enum _Step { reauth, newEmail, verifyWaiting, finalized }

class _UpdateEmailDialogWidget extends StatefulWidget {
  const _UpdateEmailDialogWidget();

  @override
  State<_UpdateEmailDialogWidget> createState() =>
      _UpdateEmailDialogWidgetState();
}

class _UpdateEmailDialogWidgetState extends State<_UpdateEmailDialogWidget>
    with SingleTickerProviderStateMixin {
  final _passwordCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _passwordVisible = false;
  final bool _isVerified = false;
  String? _errorText;
  _Step _step = _Step.reauth;
  String _newEmailSent = '';
  Timer? _pollTimer;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _passwordCtrl.dispose();
    _newEmailCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _transitionTo(_Step next) {
    _animCtrl.reverse().then((_) {
      if (mounted) {
        setState(() {
          _step = next;
          _errorText = null;
        });
        _animCtrl.forward();

        if (next == _Step.verifyWaiting) {
          _startPolling();
        }
      }
    });
  }

  // ── Polling & Auto-Sync Logic ──────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _isVerified) {
        timer.cancel();
        return;
      }

      try {
        // STRATEGY: Directly attempt to sign in with the NEW email + cached password
        // via the Identity Toolkit REST API. This only succeeds AFTER the user has
        // clicked the verification link — Firebase won't accept the new email until
        // then. This is 100% reliable and doesn't depend on the stale local SDK cache.
        final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
        final signInUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
        );
        final signInResp = await http.post(
          signInUrl,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'email': _newEmailSent,
            'password': _passwordCtrl.text,
            'returnSecureToken': true,
          }),
        );

        debugPrint(
            '[Polling] Sign-in attempt status: ${signInResp.statusCode}');

        if (signInResp.statusCode == 200) {
          // ✅ SUCCESS: The new email is now active — verification confirmed!
          debugPrint('[Polling] ✅ New email verified! Starting auto-sync...');
          timer.cancel();

          final tokenBody = json.decode(signInResp.body);
          final idToken = tokenBody['idToken'] as String?;
          final uid = tokenBody['localId'] as String?;

          if (idToken != null && uid != null) {
            // 1. Force the SDK to update its local state to the new email.
            // This is critical so that future actions (like another email change)
            // use the correct 'Original' email for security notifications.
            await FirebaseAuth.instance
                .signInWithEmailAndPassword(
                  email: _newEmailSent,
                  password: _passwordCtrl.text,
                )
                .catchError(
                    (e) => debugPrint('[Polling] SDK Sync warning: $e'));

            // 2. Patch the RTDB and finalize UI
            _patchRTDB(idToken, uid);
          }
        } else {
          // Email not yet verified — keep waiting silently
          final errBody = json.decode(signInResp.body);
          final errCode = errBody['error']?['message'] ?? 'UNKNOWN';
          debugPrint('[Polling] Not verified yet ($errCode). Retrying...');
        }
      } catch (e) {
        debugPrint('[Polling] Check error: $e');
      }
    });
  }

  Future<void> _patchRTDB(String idToken, String uid) async {
    try {
      const dbBaseUrl =
          'https://crowdsense-db-default-rtdb.asia-southeast1.firebasedatabase.app';
      final updateUrl = Uri.parse('$dbBaseUrl/users/$uid.json?auth=$idToken');
      final response = await http.patch(
        updateUrl,
        body: json.encode({'email': _newEmailSent}),
        headers: {'Content-Type': 'application/json'},
      );
      debugPrint('[AutoSync] RTDB patch status: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('[AutoSync] ✅ RTDB synced to: $_newEmailSent');
        if (mounted) {
          context.read<UserProvider>().updateProfile({'email': _newEmailSent});
          _transitionTo(_Step.finalized);
        }
      } else {
        debugPrint('[AutoSync] ❌ RTDB rejected: ${response.body}');
      }
    } catch (e) {
      debugPrint('[AutoSync] ❌ Patch failed: $e');
    }
  }

  // ── Step 1: Re-authenticate ───────────────────────────────────────────────
  Future<void> _reauth() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user found. Please log in again.');
      }

      // PROACTIVE RELOAD & SYNC:
      // We check our UserProvider email against the SDK email.
      // If they differ, the SDK is stale (common on Windows).
      final providerEmail = context.read<UserProvider>().email;
      await user.reload();
      final freshUser = FirebaseAuth.instance.currentUser;

      // FIX: Prioritize the Database-synced providerEmail over the buggy local SDK cache.
      // If the SDK says 'A' but the DB says 'B', we trust the DB and log in as 'B'.
      String targetLoginEmail =
          (providerEmail.isNotEmpty) ? providerEmail : (freshUser?.email ?? '');

      debugPrint(
          '[Reauth] Attempting login for: $targetLoginEmail (Provider: $providerEmail, SDK: ${freshUser?.email})');

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: targetLoginEmail,
        password: _passwordCtrl.text,
      );

      if (!mounted) return;
      _transitionTo(_Step.newEmail);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = _mapReauthError(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = e.toString().contains('Exception:')
            ? e.toString().split('Exception:').last
            : 'Unexpected error during verification.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 2: Send verification to new email ────────────────────────────────
  Future<void> _sendVerification() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorText = 'Session expired. Please log in again.');
      return;
    }

    final newEmail = _newEmailCtrl.text.trim();

    if (newEmail == user.email) {
      setState(() => _errorText =
          'The new email must be different from your current email.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      // 1. Force Dispatch Verification Email via Google Identity Toolkit REST API
      // We use getIdToken(true) to force the SDK to pull a fresh identity from the server.
      final idToken = await user.getIdToken(true);
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final verifyUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey');

      final response = await http.post(
        verifyUrl,
        body: json.encode({
          'requestType': 'VERIFY_AND_CHANGE_EMAIL',
          'idToken': idToken,
          'newEmail': newEmail,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        String errMsg = 'Failed to send verification email. Please try again.';
        try {
          final errBody = json.decode(response.body);
          if (errBody['error'] != null && errBody['error']['message'] != null) {
            errMsg = errBody['error']['message'];
          }
        } catch (_) {}

        throw FirebaseAuthException(
          code: 'api-error',
          message: 'Error: $errMsg',
        );
      }

      if (!mounted) return;
      _newEmailSent = newEmail;

      _transitionTo(_Step.verifyWaiting);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (e.code == 'api-error') {
          _errorText = e.message ?? 'Unknown API Error';
        } else {
          _errorText = _mapEmailError(e.code);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapReauthError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'user-mismatch':
        return 'Credential does not match the current user.';
      default:
        return 'Verification failed (code: $code). Please try again.';
    }
  }

  String _mapEmailError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already associated with another account.';
      case 'invalid-email':
        return 'The email address format is not valid.';
      case 'requires-recent-login':
        return 'This action requires a fresh sign-in. Please log out and back in, then try again.';
      case 'too-many-requests':
        return 'Too many requests. Please wait a moment and try again.';
      default:
        return 'Email update failed (code: $code). Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Container(
            width: 460,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1F2E) : cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.06),
                  blurRadius: 20,
                ),
              ],
            ),
            child: switch (_step) {
              _Step.reauth => _buildReauthView(cs),
              _Step.newEmail => _buildNewEmailView(cs),
              _Step.verifyWaiting => _buildVerifyWaitingView(cs),
              _Step.finalized => _buildFinalizedView(cs),
            },
          ),
        ),
      ),
    );
  }

  // ── Progress indicator strip ──────────────────────────────────────────────
  Widget _buildStepStrip(ColorScheme cs) {
    final labels = ['Identity', 'Target', 'Syncing', 'Secured'];
    int currentIndex = 0;
    if (_step == _Step.newEmail) currentIndex = 1;
    if (_step == _Step.verifyWaiting) currentIndex = 2;
    if (_step == _Step.finalized) currentIndex = 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, left: 4, right: 4),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (index) {
          // Even indices are steps, odd indices are dividers
          if (index.isEven) {
            final i = index ~/ 2;
            final active = i == currentIndex;
            final done = i < currentIndex;
            final color = done || active
                ? AppColors.primaryBlue
                : cs.onSurfaceVariant.withValues(alpha: 0.25);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? AppColors.primaryBlue
                        : active
                            ? AppColors.primaryBlue.withValues(alpha: 0.15)
                            : cs.onSurfaceVariant.withValues(alpha: 0.1),
                    border: Border.all(
                      color: color,
                      width: active ? 2 : 1.5,
                    ),
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: active
                                  ? AppColors.primaryBlue
                                  : cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active
                        ? AppColors.primaryBlue
                        : cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            );
          } else {
            // Divider
            final i = index ~/ 2;
            final done = i < currentIndex;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.primaryBlue
                        : cs.onSurfaceVariant.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            );
          }
        }),
      ),
    );
  }

  // ── Step 1 View ───────────────────────────────────────────────────────────
  Widget _buildReauthView(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepStrip(cs),
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: AppColors.primaryBlue, size: 28),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Verify Your Identity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'For security, please confirm your current password before changing your email.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: !_passwordVisible,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Current Password',
                prefixIcon:
                    Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
                errorText: _errorText,
                errorMaxLines: 2,
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Please enter your current password.'
                  : null,
              onFieldSubmitted: (_) => _reauth(),
            ),
            const SizedBox(height: 28),
            _ActionButton(
              label: 'Verify & Continue',
              isLoading: _isLoading,
              onPressed: _reauth,
            ),
            const SizedBox(height: 12),
            _CancelButton(onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  // ── Step 2 View ───────────────────────────────────────────────────────────
  Widget _buildNewEmailView(ColorScheme cs) {
    final user = FirebaseAuth.instance.currentUser;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepStrip(cs),

            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.alternate_email_rounded,
                    color: AppColors.primaryBlue, size: 28),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Enter New Email',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Enter the new email you\'d like to use. A verification link will be sent there.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Current email chip
            if (user?.email != null) ...[
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.email_outlined,
                          size: 14,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      const SizedBox(width: 7),
                      Text(
                        'Current: ${user!.email}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Icon(Icons.arrow_downward_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
              ),
              const SizedBox(height: 4),
            ],

            TextFormField(
              controller: _newEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'New Email Address',
                prefixIcon:
                    Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                errorText: _errorText,
                errorMaxLines: 2,
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your new email address.';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Please enter a valid email address.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _sendVerification(),
            ),
            const SizedBox(height: 28),

            _ActionButton(
              label: 'Send Verification Link',
              isLoading: _isLoading,
              onPressed: _sendVerification,
            ),
            const SizedBox(height: 12),
            _CancelButton(onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  // ── Step 3 View (The "Syncing" View) ───────────────────────────────────────
  Widget _buildVerifyWaitingView(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepStrip(cs),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(16),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Waiting for Verification...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'A link has been sent to:',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _newEmailSent,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlue,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Please click the link in your browser. This screen will automatically refresh '
            'once your account is secured.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          _CancelButton(
            label: 'Close and Sync Later',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Step 4 View (The "Secured" View) ───────────────────────────────────────
  Widget _buildFinalizedView(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepStrip(cs),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.statusSafe.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.statusSafe,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account Secured!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.statusSafe,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your email address has been successfully updated to $_newEmailSent and your database '
            'profile is fully synchronized.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _isVerified ? 'Continue to Profile' : 'Done',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.4),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(
                label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _CancelButton({
    required this.onPressed,
    this.label = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

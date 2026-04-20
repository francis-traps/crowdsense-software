import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/geometric_background.dart';
import '../../../core/widgets/custom_notification_modal.dart';
import '../../../core/providers/user_provider.dart';
import '../services/auth_service.dart';
import '../widgets/forgot_password_dialog.dart';
import '../../splash/screens/splash_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool animate;
  const LoginScreen({super.key, this.animate = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      CustomNotificationModal.show(
        context: context,
        title: "Login Failed",
        message: "Please enter both Email/Username and Password.",
        isSuccess: false,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Capture provider ref BEFORE any delays/transitions
      final userProvider = context.read<UserProvider>();

      // 1. Perform the actual authentication handshake on the Login Screen
      final payload = await _authService.login(identifier, password);

      // 2. Set the global UserProvider state
      userProvider.setUser(payload['user'], payload['userData']);

      final userData = payload['userData'] as Map<String, dynamic>;
      final bool requiresPasswordChange =
          userData['requiresPasswordChange'] == true;

      // 3. Define target route and args
      String targetRoute;
      Map<String, dynamic>? routeArgs;

      if (requiresPasswordChange) {
        targetRoute = '/force-password-change';
        routeArgs = {
          'email': payload['user'].email ?? '',
          'userData': userData
        };
      } else {
        targetRoute = '/dashboard';
      }

      if (!mounted) return;

      // 4. Navigate to Splash Screen with a smooth Fade Transition
      // We pass the already-resolved result wrapped in a Future so Splash
      // can still "await" it as part of its pulse timing logic.
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const SplashScreen(),
          settings: RouteSettings(
            arguments: {
              'authFuture': Future.value({
                'route': targetRoute,
                'args': routeArgs,
              }),
            },
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      CustomNotificationModal.show(
        context: context,
        title: "Authentication Error",
        message: errorMsg,
        isSuccess: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget withFadeInDown(Widget child) => widget.animate
        ? FadeInDown(duration: const Duration(milliseconds: 800), child: child)
        : child;

    Widget withFadeInUp(Widget child, {Duration delay = Duration.zero}) =>
        widget.animate
            ? FadeInUp(
                duration: const Duration(milliseconds: 800),
                delay: delay,
                child: child)
            : child;

    return Scaffold(
      body: GeometricBackground(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            color: Colors.transparent, // Let background shine through
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    withFadeInDown(
                      Column(
                        children: [
                          // Logo
                          Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceDark,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue
                                      .withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/images/crowdsense_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Text(
                                "CrowdSense",
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textLight,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Text(
                                  '©2026',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textLight
                                        .withValues(alpha: 0.8),
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.0,
                                  fontFamily:
                                      'Outfit'), // Ensure font consistency if possible
                              children: [
                                TextSpan(
                                  text: "DETECT. ",
                                  style: TextStyle(
                                      color: Color(0xFFEF4C33)), // Red/Orange
                                ),
                                TextSpan(
                                  text: "DIRECT. ",
                                  style: TextStyle(
                                      color: Color(0xFFC94468)), // Pink/Magenta
                                ),
                                TextSpan(
                                  text: "SECURE.",
                                  style: TextStyle(
                                      color: Color(0xFF5D3F9D)), // Purple
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    withFadeInUp(
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              "Welcome Back",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textLight,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Please sign in to continue",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textGrey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            TextField(
                              controller: _identifierController,
                              style:
                                  const TextStyle(color: AppColors.textLight),
                              decoration: const InputDecoration(
                                labelText: "Email or Username",
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              onSubmitted: (_) => _handleLogin(),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              style:
                                  const TextStyle(color: AppColors.textLight),
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordVisible
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppColors.textGrey,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible = !_isPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                              onSubmitted: (_) => _handleLogin(),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text("Log In"),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () =>
                                  ForgotPasswordDialog.show(context),
                              child: Text(
                                "Forgot Password?",
                                style: TextStyle(
                                    color: AppColors.textGrey
                                        .withValues(alpha: 0.8)),
                              ),
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
        ),
      ),
    );
  }
}

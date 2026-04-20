import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/force_password_change_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Controllers
  late AnimationController _introFadeController;   // NEW: fades whole logo in
  late AnimationController _pulseController;
  late AnimationController _wave1Controller;
  late AnimationController _wave2Controller;
  late AnimationController _wave3Controller;
  late AnimationController _cycleFadeController;   // NEW: fades pulse/waves out at end of loop
  late AnimationController _assemblyFadeOutController;

  // Animations
  late Animation<double> _introFade;   // NEW: full-logo intro fade
  late Animation<double> _pulseClip;
  late Animation<double> _wave1Fade;
  late Animation<double> _wave2Fade;
  late Animation<double> _wave3Fade;
  late Animation<double> _cycleFade;   // NEW: collective loop elements fade
  late Animation<double> _assemblyFade;

  // Tracks whether the intro fade has completed (so loop layers are shown)
  bool _introComplete = false;

  int _loopCount = 0;
  final int _maxLoops = 3;
  
  bool _isAuthMode = false;
  Future<dynamic>? _authFuture;
  bool _authCompleted = false;        // true once the auth future resolves
  String _targetRoute = '/login';
  Map<String, dynamic>? _routeArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && !_isAuthMode) {
      if (args.containsKey('authFuture')) {
        _isAuthMode = true;
        _authFuture = args['authFuture'];
        _authFuture?.then((result) {
          if (mounted) {
            // Read route + args from the smart future result
            if (result is Map<String, dynamic> && result.containsKey('route')) {
              _targetRoute = result['route'] as String;
              _routeArgs = result['args'] as Map<String, dynamic>?;
            } else {
              _targetRoute = '/dashboard';
            }
            // Mark auth done — the loop counter decides when to actually navigate
            setState(() => _authCompleted = true);
          }
        }).catchError((error) {
          if (mounted) {
            // Error handling now happens on the LoginScreen
            // If we somehow reach here, just go back to login silently
            _targetRoute = '/login';
            setState(() => _authCompleted = true);
          }
        });
      }
      // Legacy support: nextRoute arg (used by static launch, not auth mode)
      if (!_isAuthMode && args.containsKey('nextRoute')) {
        _targetRoute = args['nextRoute'];
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // 1. Intro: entire logo fades in as one unit
    _introFadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _introFade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _introFadeController, curve: Curves.easeIn));

    // 2. Pulse heartbeat (ECG Wipe Left to Right) — used during looping
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseClip = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // 3. Waves fade in consecutively — used during looping
    _wave1Controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _wave1Fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _wave1Controller, curve: Curves.easeIn));

    _wave2Controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _wave2Fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _wave2Controller, curve: Curves.easeIn));

    _wave3Controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _wave3Fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _wave3Controller, curve: Curves.easeIn));

    // 4. Cycle fade: fades out pulse + waves together at end of each loop
    _cycleFadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _cycleFade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _cycleFadeController, curve: Curves.easeIn));

    // 5. Assembly fade out
    _assemblyFadeOutController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _assemblyFade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _assemblyFadeOutController, curve: Curves.easeOut));

    // Default cycle fade to fully visible
    _cycleFadeController.value = 1.0;

    _startSequence();
  }

  void _startSequence() async {
    // Short pause so the screen renders before animating
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Fade the fully-assembled logo in as one piece
    // (pulse and waves controllers are at 0, so they're invisible during intro;
    //  we use a static full-opacity stack overlay below to show them fully)
    _pulseController.value = 1.0;   // show pulse fully during intro
    _wave1Controller.value = 1.0;
    _wave2Controller.value = 1.0;
    _wave3Controller.value = 1.0;
    _cycleFadeController.value = 1.0; // Ensure visible
    await _introFadeController.forward();
    if (!mounted) return;

    // Hold the complete logo briefly so the user can see it
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Smoothly fade out just the pulse and waves before starting the loop
    await _cycleFadeController.reverse();
    if (!mounted) return;

    // Reset loop-layer controllers so the looping animation builds from scratch
    _pulseController.reset();
    _wave1Controller.reset();
    _wave2Controller.reset();
    _wave3Controller.reset();
    _cycleFadeController.value = 1.0; // Re-enable for the building phase
    setState(() => _introComplete = true);

    // Start the looping pulse-and-waves sequence
    _runLoop();
  }
  
  bool _shouldFinishAnimation() {
    if (_isAuthMode) {
      // Auth mode: minimum 2 loops must complete AND auth must be done.
      // This guarantees the splash always shows for at least 2 beats,
      // even if the server responds instantly.
      return _loopCount >= 1 && _authCompleted;
    } else {
      // Standard app-launch mode: always runs exactly 3 loops
      return _loopCount >= _maxLoops;
    }
  }

  void _runLoop() async {
    if (!mounted) return;

    // 1. ECG Pulse wipe left to right
    await _pulseController.forward();
    
    // 2. Waves consecutively
    await _wave1Controller.forward();
    await _wave2Controller.forward();
    await _wave3Controller.forward();
    
    // 3. Hold briefly while fully visible
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    _loopCount++;

    // 4. Check if this was the last mandated loop
    if (_shouldFinishAnimation()) {
      // Hold the COMPLETE logo for a final beat before transition
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      
      // Fade out the entire assembly together (C + pulses + waves + text)
      await _assemblyFadeOutController.forward();
      if (!mounted) return;

      _navigateToTarget();
      return;
    }

    // 5. If not finished, smoothly fade out loop elements and repeat
    await _cycleFadeController.reverse();
    if (!mounted) return;

    _pulseController.reset();
    _wave1Controller.reset();
    _wave2Controller.reset();
    _wave3Controller.reset();
    _cycleFadeController.value = 1.0; // Ready for next cycle

    // Minor delay before starting the next loop beat
    await Future.delayed(const Duration(milliseconds: 300));
    _runLoop();
  }

  void _navigateToTarget() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1000),
        pageBuilder: (context, animation, secondaryAnimation) {
          switch (_targetRoute) {
            case '/login':
              return const LoginScreen(animate: false);
            case '/dashboard':
              return const DashboardScreen();
            case '/force-password-change':
              return ForcePasswordChangeScreen(
                email: (_routeArgs?['email'] as String?) ?? '',
                userData: (_routeArgs?['userData'] as Map<String, dynamic>?) ?? {},
              );
            default:
              return const LoginScreen(animate: false);
          }
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _introFadeController.dispose();
    _pulseController.dispose();
    _wave1Controller.dispose();
    _wave2Controller.dispose();
    _wave3Controller.dispose();
    _cycleFadeController.dispose();
    _assemblyFadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double logoWidth = 200.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo + Title group — fade out together on assembly fade ─────────
            FadeTransition(
              opacity: _assemblyFade,
              child: FadeTransition(
                // Intro fade: the whole logo comes in as one unit
                opacity: _introFade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Animated logo stack ──────────────────────────────────
                    SizedBox(
                      width: logoWidth,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // C is always fully opaque once intro starts
                          Image.asset('assets/images/C.png', width: logoWidth, fit: BoxFit.contain),

                          // Cycle fade: wraps looping elements for smooth transitions
                          FadeTransition(
                            opacity: _cycleFade,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Pulse: during intro it's fully visible (controller.value=1);
                                // after intro resets to 0 and animates via ClipRect
                                AnimatedBuilder(
                                  animation: _pulseClip,
                                  builder: (context, child) => _introComplete
                                      ? ClipRect(
                                          clipper: _LeftToRightClipper(progress: _pulseClip.value),
                                          child: child,
                                        )
                                      : child!,
                                  child: Image.asset('assets/images/PULSE.png', width: logoWidth, fit: BoxFit.contain),
                                ),

                                // Waves: fully visible during intro, animated after
                                FadeTransition(
                                  opacity: _wave1Fade,
                                  child: Image.asset('assets/images/WAVE 1.png', width: logoWidth, fit: BoxFit.contain),
                                ),
                                FadeTransition(
                                  opacity: _wave2Fade,
                                  child: Image.asset('assets/images/WAVE 2.png', width: logoWidth, fit: BoxFit.contain),
                                ),
                                FadeTransition(
                                  opacity: _wave3Fade,
                                  child: Image.asset('assets/images/WAVE 3.png', width: logoWidth, fit: BoxFit.contain),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── App name + tagline — always visible once intro fades in ─
                    const SizedBox(height: 20),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Text(
                          'CrowdSense',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE8EAF6),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Text(
                            '©2026',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFE8EAF6).withValues(alpha: 0.8),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          fontFamily: 'Outfit',
                        ),
                        children: [
                          TextSpan(text: 'DETECT. ', style: TextStyle(color: Color(0xFFEF4C33))),
                          TextSpan(text: 'DIRECT. ', style: TextStyle(color: Color(0xFFC94468))),
                          TextSpan(text: 'SECURE.', style: TextStyle(color: Color(0xFF5D3F9D))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Loading Spinner (auth mode only — outside the fade group) ─────
            if (_isAuthMode) ...[ 
              const SizedBox(height: 36),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeftToRightClipper extends CustomClipper<Rect> {
  final double progress;
  
  _LeftToRightClipper({required this.progress});
  
  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }
  
  @override
  bool shouldReclip(_LeftToRightClipper oldClipper) => progress != oldClipper.progress;
}


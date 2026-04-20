import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/force_password_change_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

import 'features/splash/screens/splash_screen.dart';
import 'core/widgets/siren_active_dialog.dart';

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:provider/provider.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/siren_provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
    debugPrint(
        '[CrowdSense] .env loaded successfully. DB URL: ${dotenv.env['FIREBASE_DATABASE_URL']}');
  } catch (e) {
    debugPrint('[CrowdSense] WARNING: Failed to load .env file: $e');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // If it's already initialized, ignore the exception
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  // Explicitly set the RTDB URL to the correct asia-southeast1 region
  // This prevents the "Database lives in a different region" error on Android
  final dbUrl = dotenv.env['FIREBASE_DATABASE_URL'] ??
      'https://crowdsense-db-default-rtdb.asia-southeast1.firebasedatabase.app';
  // Go offline BEFORE setting the URL to prevent the C++ RTDB SDK assertion
  // (connection_state_ == kDisconnected). The SDK auto-connects after
  // initializeApp, so setting databaseURL while connected can trigger abort().
  // The login flow will call goOnline() after authentication completes.
  // NOTE: This workaround is ONLY needed on desktop (Windows/Linux/macOS).
  // On mobile (Android/iOS), the native SDK handles this correctly and
  // goOffline() would prevent RTDB listeners from ever receiving data.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    FirebaseDatabase.instance.goOffline();
  }
  FirebaseDatabase.instance.databaseURL = dbUrl;
  debugPrint('[CrowdSense] Firebase RTDB URL set to: $dbUrl');

  // Catch the firebase_auth Windows threading bug at the zone level
  // so it doesn't hard-crash the "Lost connection to device"
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error.toString().contains('firebase_auth_plugin') ||
        error.toString().contains('non-platform thread')) {
      return true; // silently handle the plugin's false-alarm bug
    }
    return false; // let all other real errors crash normally
  };

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(500, 950),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'CrowdSense App',
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SirenProvider()),
      ],
      child: const CrowdSenseApp(),
    ),
  );
}

class CrowdSenseApp extends StatelessWidget {
  const CrowdSenseApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Consumer<SirenProvider>(
          builder: (context, sirenProvider, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'CrowdSense App',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.trackpad,
                },
                scrollbars: false,
              ),
              builder: (context, child) {
                return Stack(
                  children: [
                    if (child != null) child,
                    if (sirenProvider.isSirenActive)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        bottom: sirenProvider.isBottomNavVisible ? 130 : 40,
                        left: 16,
                        right: 16,
                        child: _GlobalSirenBar(
                          title: sirenProvider.activeSirenTitle!,
                          icon: sirenProvider.activeSirenIcon!,
                          color: sirenProvider.activeSirenColor!,
                          onTap: () {
                            final navContext = navigatorKey.currentContext;
                            if (navContext != null) {
                              SirenActiveDialog.show(navContext, sirenProvider);
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
              initialRoute: '/splash',
              routes: {
                '/splash': (context) => const SplashScreen(),
                '/login': (context) => const LoginScreen(),
                '/force-password-change': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
                  return ForcePasswordChangeScreen(
                    email: args['email'] as String,
                    userData: args['userData'] as Map<String, dynamic>,
                  );
                },
                '/dashboard': (context) => const DashboardScreen(),
              },
            );
          },
        );
      },
    );
  }
}

class _GlobalSirenBar extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GlobalSirenBar({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E2433).withValues(alpha: 0.95)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 12,
                spreadRadius: 2),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.8, end: 1.1),
              duration: const Duration(milliseconds: 600),
              builder: (context, val, child) => Transform.scale(
                  scale: val, child: Icon(icon, color: color, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "${title.toUpperCase()} IS ACTIVE",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: color,
                    decoration: TextDecoration.none),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.power_settings_new_rounded,
                size: 16, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

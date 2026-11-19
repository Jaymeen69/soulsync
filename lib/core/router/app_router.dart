import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'route_names.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/email_verification_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/create_profile_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/connect/presentation/screens/connect_screen.dart';
import '../../features/together/presentation/screens/together_screen.dart';
import '../../features/memories/presentation/screens/memories_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../shared/widgets/main_scaffold.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: RouteNames.splash,
    debugLogDiagnostics: false, // Set true only during debug
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final isAuthRoute = [
        RouteNames.login,
        RouteNames.register,
        RouteNames.onboarding,
        RouteNames.emailVerification,
        RouteNames.forgotPassword,
        RouteNames.createProfile,
        RouteNames.splash,
      ].contains(state.matchedLocation);

      // Not logged in and trying to access protected route
      if (!isAuthenticated && !isAuthRoute) {
        return RouteNames.login;
      }

      // Logged in but on auth route (except splash/create-profile)
      if (isAuthenticated &&
          isAuthRoute &&
          state.matchedLocation != RouteNames.splash &&
          state.matchedLocation != RouteNames.createProfile) {
        return RouteNames.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RouteNames.emailVerification,
        builder: (context, state) {
          if (state.extra is Map<String, dynamic>) {
            final map = state.extra as Map<String, dynamic>;
            return EmailVerificationScreen(
              email: map['email'] as String?,
              initialOtp: map['dev_otp'] as String?,
            );
          }
          return EmailVerificationScreen(email: state.extra as String?);
        },
      ),
      GoRoute(
        path: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RouteNames.createProfile,
        builder: (context, state) => const CreateProfileScreen(),
      ),
      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: RouteNames.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: RouteNames.connect,
            builder: (context, state) => const ConnectScreen(),
          ),
          GoRoute(
            path: RouteNames.together,
            builder: (context, state) => const TogetherScreen(),
          ),
          GoRoute(
            path: RouteNames.memories,
            builder: (context, state) => const MemoriesScreen(),
          ),
          GoRoute(
            path: RouteNames.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found: ${state.error}'),
          ],
        ),
      ),
    ),
  );
});

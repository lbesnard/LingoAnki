import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'l10n/app_localizations.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/lessons_screen.dart';
import 'screens/sentences_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connection_badge.dart';
import 'widgets/scaled_app.dart';
import 'services/auth_service.dart';
import 'services/sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await WakelockPlus.enable();
  runApp(const LingoDiaryApp());
}

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final token = await AuthService.getToken();
    final isLogin = state.matchedLocation == '/login';

    // If no token and not on login page, redirect to login
    if (token == null && !isLogin) return '/login';

    // If has token and on login page, redirect to home
    // BUT only if this is the initial route or a direct navigation to /login
    // Don't redirect if we just navigated to /login (like during sign out)
    if (token != null && isLogin) {
      // Check if this is a programmatic navigation to /login (sign out)
      // by looking at the previous location in the router state
      final uri = state.uri;
      // If there are no query parameters and it's a simple /login, redirect to home
      // If there are any indicators this was a sign-out navigation, allow it
      if (uri.queryParameters.isEmpty && uri.fragment.isEmpty) {
        return '/';
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/review', builder: (_, __) => const SentencesScreen()),
        GoRoute(path: '/lessons', builder: (_, __) => const LessonsScreen()),
        GoRoute(path: '/diary', builder: (_, __) => const DiaryScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),
  ],
);

class LingoDiaryApp extends StatelessWidget {
  const LingoDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LingoDiary',
      routerConfig: _router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return ScaledApp(child: child ?? Container());
      },
    );
  }
}

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  void _showHelpDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.helpTitle),
        content: SingleChildScrollView(child: Text(l10n.helpBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.helpClose),
          ),
        ],
      ),
    );
  }

  int _currentIndex(String location) {
    if (location.startsWith('/review')) return 1;
    if (location.startsWith('/lessons')) return 2;
    if (location.startsWith('/diary')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return ListenableBuilder(
      listenable: SyncManager.instance,
      builder: (context, _) {
        final sync = SyncManager.instance;
        return Scaffold(
          appBar: AppBar(
            title: const Text('LingoDiary'),
            actions: [
              const ConnectionBadge(),
              IconButton(
                tooltip: 'Help',
                icon: const Icon(Icons.help_outline),
                onPressed: () => _showHelpDialog(context),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          body: child,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sync.isSyncing)
                Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(
                              value: sync.progress,
                              minHeight: 5,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sync.message,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (sync.progress != null)
                        Text(
                          '${(sync.progress! * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: sync.cancel,
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 28)),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                )
              else if (sync.message.isNotEmpty && sync.filesDownloaded >= 0)
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(sync.message, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              BottomNavigationBar(
                currentIndex: _currentIndex(location),
                onTap: (i) {
                  switch (i) {
                    case 0:
                      context.go('/');
                    case 1:
                      context.go('/review');
                    case 2:
                      context.go('/lessons');
                    case 3:
                      context.go('/diary');
                  }
                },
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                      icon: const Icon(Icons.home_outlined), label: 'Home'),
                  BottomNavigationBarItem(
                      icon: const Icon(Icons.quiz_outlined), label: 'Review'),
                  BottomNavigationBarItem(
                      icon: const Icon(Icons.headphones),
                      label: AppLocalizations.of(context).navLessons),
                  BottomNavigationBarItem(
                      icon: const Icon(Icons.book),
                      label: AppLocalizations.of(context).navDiary),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

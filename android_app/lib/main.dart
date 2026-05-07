import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'l10n/app_localizations.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/lessons_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connection_badge.dart';
import 'services/auth_service.dart';
import 'services/sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.lingoanki.audio',
    androidNotificationChannelName: 'LingoAnki Audio',
    androidNotificationOngoing: true,
  );
  runApp(const LingoDiaryApp());
}

class LingoDiaryApp extends StatelessWidget {
  const LingoDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LingoDiary',
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fr'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      routes: {
        '/home': (_) => const MainShell(),
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await AuthService.getToken();
    setState(() {
      _loggedIn = token != null;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn ? const MainShell() : const LoginScreen();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    LessonsScreen(),
    DiaryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: _screens[_currentIndex],
          // Persistent sync progress bar above the bottom nav
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
                // Show last result briefly — cleared on next sync
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(sync.message,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                items: [
                  BottomNavigationBarItem(
                      icon: const Icon(Icons.home_outlined),
                      label: 'Home'),
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

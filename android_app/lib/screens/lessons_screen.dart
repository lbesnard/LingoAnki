import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../services/sync_service.dart';
import 'player_screen.dart';

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;
  Set<String> _syncedBases = {};

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenServer();
    SyncManager.instance.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (!SyncManager.instance.isSyncing) {
      _loadFromCacheThenServer();
    }
  }  /// Show cached data immediately, then silently refresh from server.
  Future<void> _loadFromCacheThenServer() async {
    // 1. Show cache straight away (no long spinner)
    final cached = await LocalDbService.getLessons();
    if (mounted) {
      setState(() {
        _lessons = _parseCachedLessons(cached);
        _loading = false;
      });
    }
    _checkSyncStatus(_lessons);

    // 2. Try server in background; update if it responds
    try {
      final remote = await ApiService.getLessons();
      await LocalDbService.saveLessons(remote);
      if (mounted) setState(() => _lessons = remote);
      _checkSyncStatus(remote);
    } catch (_) {
      // Server unreachable — cached data is already showing, nothing to do
    }
  }

  Future<void> _checkSyncStatus(List<Map<String, dynamic>> lessons) async {
    final synced = <String>{};
    for (final lesson in lessons) {
      final base = lesson['base'] as String? ?? '';
      final variants = lesson['variants'] as Map<String, dynamic>? ?? {};
      for (final filename in variants.values) {
        final mp3Path = await SyncService.localPath('TPRS/$filename');
        if (await File(mp3Path).exists()) {
          synced.add(base);
          break;
        }
      }
    }
    if (mounted) setState(() => _syncedBases = synced);
  }

  /// Pull-to-refresh: explicitly sync all then reload.
  Future<void> _onRefresh() async {
    try {
      final remote = await ApiService.getLessons();
      await LocalDbService.saveLessons(remote);
      if (mounted) setState(() => _lessons = remote);
      _checkSyncStatus(remote);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server unreachable — showing cached lessons'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _parseCachedLessons(
      List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final variantsRaw = row['variants_json'] as String? ?? '{}';
      Map<String, dynamic> variants = {};
      try {
        variants = jsonDecode(variantsRaw) as Map<String, dynamic>;
      } catch (_) {}
      return {
        'base': row['base'],
        'display': row['display'],
        'variants': variants,
      };
    }).toList();
  }

  Widget _buildLessonIcon(Map<String, dynamic> lesson) {
    final base = lesson['base'] as String? ?? '';
    final srs = lesson['srs'] as Map<String, dynamic>?;

    if (srs != null) {
      final total = (srs['total'] as int?) ?? 0;
      final mastered = (srs['mastered'] as int?) ?? 0;
      if (total > 0 && mastered == total) {
        return const Icon(Icons.star, color: Colors.amber);
      }
      if (mastered > 0) {
        return const Icon(Icons.check_circle_outline, color: Colors.blue);
      }
    }

    return _syncedBases.contains(base)
        ? const Icon(Icons.check_circle, color: Colors.green)
        : const Icon(Icons.radio_button_unchecked, color: Colors.grey);
  }

  Widget _buildLessonSubtitle(
      Map<String, dynamic> lesson, Map<String, dynamic> variants) {
    final srs = lesson['srs'] as Map<String, dynamic>?;
    final variantStr = variants.keys.join(' · ');

    if (srs != null) {
      final total = (srs['total'] as int?) ?? 0;
      final mastered = (srs['mastered'] as int?) ?? 0;
      return Text(
        '$variantStr  ·  $mastered/$total mastered',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Text(
      variantStr,
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    );
  }

  void _openLesson(Map<String, dynamic> lesson) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(lesson: lesson)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: SyncManager.instance,
                  builder: (_, __) => Text(
                    SyncManager.instance.isSyncing
                        ? SyncManager.instance.message
                        : '',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: SyncManager.instance,
                builder: (_, __) {
                  final syncing = SyncManager.instance.isSyncing;
                  return syncing
                      ? TextButton.icon(
                          onPressed: SyncManager.instance.cancel,
                          icon: const Icon(Icons.stop,
                              size: 16, color: Colors.red),
                          label: const Text('Cancel',
                              style: TextStyle(color: Colors.red)),
                        )
                      : ElevatedButton.icon(
                          onPressed: SyncManager.instance.syncAll,
                          icon: const Icon(Icons.sync, size: 16),
                          label: const Text('Sync All'),
                        );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _lessons.isEmpty
                  ? const Center(
                      child: Text(
                          'No lessons yet.\nTap Sync All to download.',
                          textAlign: TextAlign.center))
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        itemCount: _lessons.length,
                        itemBuilder: (ctx, i) {
                          final lesson = _lessons[i];
                          final variants =
                              lesson['variants'] as Map<String, dynamic>? ?? {};
                          return ListTile(
                            leading: _buildLessonIcon(lesson),
                            title: Text(lesson['display'] as String),
                            subtitle: _buildLessonSubtitle(lesson, variants),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openLesson(lesson),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

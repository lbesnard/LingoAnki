import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import 'player_screen.dart';

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    SyncManager.instance.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    // Refresh lesson list when a global sync finishes
    if (!SyncManager.instance.isSyncing) {
      _loadLessons();
    }
  }

  Future<void> _loadLessons() async {
    setState(() => _loading = true);
    try {
      final remote = await ApiService.getLessons();
      await LocalDbService.saveLessons(remote);
      setState(() => _lessons = remote);
    } catch (_) {
      final cached = await LocalDbService.getLessons();
      setState(() => _lessons = cached.map((row) {
            final variantsRaw = row['variants_json'] as String;
            Map<String, dynamic> variants = {};
            try {
              variants = jsonDecode(variantsRaw) as Map<String, dynamic>;
            } catch (_) {}
            return {
              'base': row['base'],
              'display': row['display'],
              'variants': variants,
            };
          }).toList());
    }
    setState(() => _loading = false);
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
                  : ListView.builder(
                      itemCount: _lessons.length,
                      itemBuilder: (ctx, i) {
                        final lesson = _lessons[i];
                        final variants =
                            lesson['variants'] as Map<String, dynamic>? ?? {};
                        return ListTile(
                          leading: const Icon(Icons.audiotrack),
                          title: Text(lesson['display'] as String),
                          subtitle: Text(
                            variants.keys.join(' · '),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openLesson(lesson),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

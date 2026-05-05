import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
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
  bool _syncing = false;
  bool _cancelSync = false;
  String _syncMessage = '';

  @override
  void initState() {
    super.initState();
    _loadLessons();
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

  Future<void> _syncAll() async {
    setState(() {
      _syncing = true;
      _cancelSync = false;
      _syncMessage = 'Syncing…';
    });
    try {
      final count = await SyncService.syncFromServer(
        onProgress: (msg) => setState(() => _syncMessage = msg),
        isCancelled: () => _cancelSync,
      );
      setState(() => _syncMessage =
          _cancelSync ? 'Sync cancelled.' : 'Synced $count file(s) ✓');
      await _loadLessons();
    } catch (e) {
      setState(() => _syncMessage = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _openLesson(Map<String, dynamic> lesson) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(lesson: lesson),
      ),
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
                child: Text(
                  _syncMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_syncing)
                TextButton.icon(
                  onPressed: () => setState(() => _cancelSync = true),
                  icon: const Icon(Icons.stop, size: 16, color: Colors.red),
                  label: const Text('Cancel',
                      style: TextStyle(color: Colors.red)),
                )
              else
                ElevatedButton.icon(
                  onPressed: _sync,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync All'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _lessons.isEmpty
                  ? const Center(
                      child: Text('No lessons yet.\nTap Sync All to download.',
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

  // alias so both the button label change and the call site compile
  void _sync() => _syncAll();
}

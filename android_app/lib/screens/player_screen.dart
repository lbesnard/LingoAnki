import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_manager.dart';
import '../services/sync_service.dart';

class PlayerScreen extends StatefulWidget {
  final Map<String, dynamic> lesson;

  const PlayerScreen({super.key, required this.lesson});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AudioPlayer _player;
  String _markdownContent = '';
  bool _audioReady = false;

  late List<String> _variantNames;
  late String _currentVariant;
  late Map<String, dynamic> _variants;

  String _kwSentence = 'SETNING:';
  String _kwQuestion = 'SPØRSMÅL:';
  String _kwAnswer = 'SVAR:';

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _variants = widget.lesson['variants'] as Map<String, dynamic>? ?? {};
    _variantNames = _variants.keys.toList();
    _currentVariant = _variantNames.isNotEmpty ? _variantNames.first : '';
    _loadKeywords().then((_) => _loadVariant(_currentVariant));

    // Reload content when a sync started from this screen completes
    SyncManager.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (!SyncManager.instance.isSyncing && mounted) {
      _loadVariant(_currentVariant);
    }
  }

  Future<void> _loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _kwSentence = prefs.getString('tprs_sentence') ?? 'SETNING:';
      _kwQuestion = prefs.getString('tprs_question') ?? 'SPØRSMÅL:';
      _kwAnswer = prefs.getString('tprs_answer') ?? 'SVAR:';
    });
  }

  Future<void> _loadVariant(String variantName) async {
    if (variantName.isEmpty) return;
    final filename = _variants[variantName] as String? ?? '';
    final mp3Path = await SyncService.localPath('TPRS/$filename');
    final mdPath =
        mp3Path.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '.md');

    await _player.stop();
    setState(() {
      _audioReady = false;
      _markdownContent = '';
    });

    final audioFile = File(mp3Path);
    if (await audioFile.exists()) {
      await _player.setFilePath(mp3Path);
      setState(() => _audioReady = true);
    }

    final mdFile = File(mdPath);
    if (await mdFile.exists()) {
      setState(() => _markdownContent = mdFile.readAsStringSync());
    }
  }

  void _triggerSync() {
    final base = widget.lesson['base'] as String;
    SyncManager.instance.syncLesson(base);
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_onSyncChanged);
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── TPRS renderer ─────────────────────────────────────────────────────────────

  Widget _buildTprsContent() {
    if (_markdownContent.isEmpty) {
      return const Center(child: Text('No content — tap Sync to download.'));
    }

    final blocks = _markdownContent.split(RegExp(r'\n{2,}'));
    final widgets = <Widget>[];

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.trim().split('\n');
      final lineWidgets = <Widget>[];
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        lineWidgets.add(_buildLine(line));
      }
      if (lineWidgets.isNotEmpty) {
        widgets.add(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lineWidgets,
        ));
        widgets.add(const SizedBox(height: 16));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: widgets,
    );
  }

  Widget _buildLine(String line) {
    if (line.startsWith(_kwSentence)) {
      final text = line.substring(_kwSentence.length).trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '$_kwSentence $text',
          style: const TextStyle(
              color: Color(0xFF3F51B5),
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
      );
    } else if (line.startsWith(_kwQuestion)) {
      final text = line.substring(_kwQuestion.length).trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 2, top: 4),
        child: Text(
          '$_kwQuestion $text',
          style: const TextStyle(
              color: Color(0xFFE65100),
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      );
    } else if (line.startsWith(_kwAnswer)) {
      final text = line.substring(_kwAnswer.length).trim();
      return Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(
          '$_kwAnswer $text',
          style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 14),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(line,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.lesson['display'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          ListenableBuilder(
            listenable: SyncManager.instance,
            builder: (_, __) {
              final syncing = SyncManager.instance.isSyncing;
              return IconButton(
                tooltip: syncing ? 'Sync in progress…' : 'Sync this lesson',
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                onPressed: syncing ? null : _triggerSync,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Variant selector ─────────────────────────────────────────────
          if (_variantNames.length > 1)
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: _variantNames
                      .map((v) => ButtonSegment<String>(
                            value: v,
                            label: Text(v,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  selected: {_currentVariant},
                  onSelectionChanged: (sel) {
                    setState(() => _currentVariant = sel.first);
                    _loadVariant(sel.first);
                  },
                ),
              ),
            ),

          // ── Audio controls ────────────────────────────────────────────────
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (_, posSnap) {
                    return StreamBuilder<Duration?>(
                      stream: _player.durationStream,
                      builder: (_, durSnap) {
                        final position = posSnap.data ?? Duration.zero;
                        final duration = durSnap.data ?? Duration.zero;
                        final progress = duration.inMilliseconds > 0
                            ? position.inMilliseconds / duration.inMilliseconds
                            : 0.0;
                        return Column(
                          children: [
                            Slider(
                              value: progress.clamp(0.0, 1.0),
                              onChanged: _audioReady
                                  ? (v) => _player.seek(Duration(
                                      milliseconds:
                                          (v * duration.inMilliseconds)
                                              .round()))
                                  : null,
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(position)),
                                Text(_formatDuration(duration)),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      onPressed: _audioReady
                          ? () => _player.seek(
                              _player.position - const Duration(seconds: 10))
                          : null,
                    ),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (_, snap) {
                        final playing = snap.data?.playing ?? false;
                        return IconButton(
                          iconSize: 48,
                          icon: Icon(playing
                              ? Icons.pause_circle
                              : Icons.play_circle),
                          onPressed: _audioReady
                              ? () =>
                                  playing ? _player.pause() : _player.play()
                              : null,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      onPressed: _audioReady
                          ? () => _player.seek(
                              _player.position + const Duration(seconds: 10))
                          : null,
                    ),
                  ],
                ),
                if (!_audioReady)
                  const Text('Audio not synced yet — tap ⟳ in the toolbar.',
                      style: TextStyle(color: Colors.orange, fontSize: 12)),
              ],
            ),
          ),

          // ── TPRS text content ─────────────────────────────────────────────
          Expanded(child: _buildTprsContent()),
        ],
      ),
    );
  }
}

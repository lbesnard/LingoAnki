import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import 'stats_screen.dart';

/// Anki-style sentence review screen.
///
/// Loads sentences due for review from [ApiService.getDueSentences],
/// then presents them one at a time:
///   1. Sentence in study language (always visible)
///   2. Tap "Show translation" → reveals input-language sentence + tips
///   3. Tap "Show Q&A" → reveals Q&A pairs with translations
///   4. Score buttons: Again / Hard / Good / Easy
class SentencesScreen extends StatefulWidget {
  const SentencesScreen({super.key});

  @override
  State<SentencesScreen> createState() => _SentencesScreenState();
}

class _SentencesScreenState extends State<SentencesScreen> {
  List<Map<String, dynamic>> _sentences = [];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;

  bool _showTranslation = false;
  bool _showQA = false;
  bool _scoring = false;
  bool _offlineMode = false;
  bool _playingAllQa = false;
  bool _syncing = false;

  static const _cacheKey = 'sentences_due_cache';

  // Sentence audio player
  late AudioPlayer _player;
  bool _audioLoaded = false;
  bool _audioPlaying = false;
  bool _audioDownloading = false;
  bool _audioUnavailable = false;

  // Q&A audio player
  late AudioPlayer _qaPlayer;
  bool _qaPlaying = false;
  String? _activeQaKey; // e.g. '0_q', '1_a'
  bool _qaDownloading = false;
  String? _qaDownloadingKey;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        // Show play icon (not stop) once the clip finishes naturally
        final done = state.processingState == ProcessingState.completed;
        setState(() => _audioPlaying = state.playing && !done);
      }
    });

    _qaPlayer = AudioPlayer();
    _qaPlayer.playerStateStream.listen((state) {
      if (mounted) {
        final done = state.processingState == ProcessingState.completed;
        setState(() {
          _qaPlaying = state.playing && !done;
          if (done) _activeQaKey = null;
        });
      }
    });

    _loadSentences();
  }

  @override
  void dispose() {
    _player.dispose();
    _qaPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSentences() async {
    setState(() {
      _loading = true;
      _error = null;
      _offlineMode = false;
    });
    try {
      final sentences = await ApiService.getDueSentences(limit: 20);
      // Cache for offline use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(sentences));
      if (mounted) {
        setState(() {
          _sentences = sentences;
          _currentIndex = 0;
          _loading = false;
        });
        _loadAudio(autoPlay: true);
      }
    } catch (_) {
      // Try offline cache
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_cacheKey);
        if (cached != null) {
          final sentences =
              List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
          if (mounted) {
            setState(() {
              _sentences = sentences;
              _currentIndex = 0;
              _loading = false;
              _offlineMode = true;
            });
            _loadAudio(autoPlay: true);
          }
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Offline — sync the app when connected to load new sentences.';
        });
      }
    }
  }

  Future<void> _loadAudio({bool autoPlay = false}) async {
    if (_sentences.isEmpty) return;
    final item = _sentences[_currentIndex];
    final audioPath = item['sentence_audio_path'] as String? ?? '';
    if (audioPath.isEmpty) {
      setState(() {
        _audioLoaded = false;
        _audioUnavailable = false;
      });
      return;
    }
    try {
      // On Android: check/download local cache first.
      if (!kIsWeb && !File(await SyncService.localPath(audioPath)).existsSync()) {
        setState(() {
          _audioDownloading = true;
          _audioLoaded = false;
          _audioUnavailable = false;
        });
        final ok = await SyncService.downloadFile(audioPath);
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _audioDownloading = false;
            _audioUnavailable = true;
          });
          return;
        }
        setState(() => _audioDownloading = false);
      }
      final uri = await SyncService.audioUri(audioPath);
      await _player.setAudioSource(AudioSource.uri(uri));
      if (mounted) {
        setState(() { _audioLoaded = true; _audioUnavailable = false; });
        if (autoPlay) _player.play();
      }
    } catch (_) {
      if (mounted) setState(() { _audioLoaded = false; _audioDownloading = false; _audioUnavailable = true; });
    }
  }

  void _playAudio() async {
    // If audio is not ready, try to load it on demand (and autoplay)
    if (!_audioLoaded) {
      _loadAudio(autoPlay: true);
      return;
    }
    // Stop any Q&A playback first
    if (_qaPlaying) {
      await _qaPlayer.stop();
      setState(() { _qaPlaying = false; _activeQaKey = null; });
    }
    // If clip already played to end, seek back to start
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    _player.play();
  }

  /// Play a Q&A audio clip. Downloads the file if not cached.
  Future<void> _playQaAudio(int pairIndex, String type, String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) return;
    final key = '${pairIndex}_$type';

    // If already playing this clip → stop it
    if (_activeQaKey == key && _qaPlaying) {
      await _qaPlayer.stop();
      setState(() { _qaPlaying = false; _activeQaKey = null; });
      return;
    }

    // Stop main sentence player
    if (_audioPlaying) await _player.stop();

    try {
      // On Android: check/download local cache first.
      if (!kIsWeb && !File(await SyncService.localPath(audioPath)).existsSync()) {
        setState(() { _qaDownloading = true; _qaDownloadingKey = key; });
        final ok = await SyncService.downloadFile(audioPath);
        if (!mounted) return;
        setState(() { _qaDownloading = false; _qaDownloadingKey = null; });
        if (!ok) return;
      }
      final uri = await SyncService.audioUri(audioPath);
      setState(() { _activeQaKey = key; _qaPlaying = true; });
      await _qaPlayer.setAudioSource(AudioSource.uri(uri));
      _qaPlayer.play();
    } catch (_) {
      if (mounted) setState(() { _qaDownloading = false; _qaDownloadingKey = null; });
    }
  }

   /// Play all Q&A audio clips for the current sentence in sequence.
  /// Calling again while playing stops playback.
  Future<void> _playAllQa(List<Map<String, dynamic>> qa) async {
    if (_playingAllQa) {
      setState(() => _playingAllQa = false);
      await _qaPlayer.stop();
      setState(() { _qaPlaying = false; _activeQaKey = null; });
      return;
    }
    setState(() => _playingAllQa = true);
    if (_audioPlaying) await _player.stop();

    for (var i = 0; i < qa.length; i++) {
      for (final type in ['q', 'a']) {
        if (!_playingAllQa || !mounted) return;
        final path = type == 'q'
            ? qa[i]['question_audio_path'] as String? ?? ''
            : qa[i]['answer_audio_path'] as String? ?? '';
        if (path.isEmpty) continue;

        if (!kIsWeb && !File(await SyncService.localPath(path)).existsSync()) {
          final ok = await SyncService.downloadFile(path);
          if (!ok || !mounted) continue;
        }

        if (!_playingAllQa || !mounted) return;
        final key = '${i}_$type';
        setState(() { _activeQaKey = key; _qaPlaying = true; });
        final uri = await SyncService.audioUri(path);
        await _qaPlayer.setAudioSource(AudioSource.uri(uri));
        await _qaPlayer.seek(Duration.zero);
        _qaPlayer.play();

        // Safe evaluation: Wait specifically for the audio track to hit completed state.
        // It skips checking structural state combinations that can drop the first block early.
        await _qaPlayer.processingStateStream.firstWhere(
          (state) => state == ProcessingState.completed || !_playingAllQa || !mounted
        );
      }
    }

    if (mounted) {
      setState(() { _playingAllQa = false; _qaPlaying = false; _activeQaKey = null; });
    }
  }

  /// Downloads all audio files for the current sentence (sentence + Q&A).
  Future<void> _syncCurrentLessonAudio() async {
    if (_sentences.isEmpty || _syncing) return;
    final item = _sentences[_currentIndex];
    await _syncItemAudio(item);
    if (mounted) {
      setState(() => _syncing = false);
      _loadAudio();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio synced'), duration: Duration(seconds: 2)),
      );
    }
  }

  /// Downloads audio for all remaining sentences in the review queue.
  Future<void> _syncAllAudio() async {
    if (_sentences.isEmpty || _syncing) return;
    setState(() => _syncing = true);
    int count = 0;
    for (var i = _currentIndex; i < _sentences.length; i++) {
      if (!mounted) return;
      await _syncItemAudio(_sentences[i]);
      count++;
    }
    if (mounted) {
      setState(() => _syncing = false);
      _loadAudio();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced audio for $count sentences'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Helper: collect and download all audio paths for [item].
  Future<void> _syncItemAudio(Map<String, dynamic> item) async {
    final paths = <String>[];
    final sentAudio = item['sentence_audio_path'] as String? ?? '';
    if (sentAudio.isNotEmpty) paths.add(sentAudio);
    final qa = (item['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final pair in qa) {
      final q = pair['question_audio_path'] as String? ?? '';
      final a = pair['answer_audio_path'] as String? ?? '';
      if (q.isNotEmpty) paths.add(q);
      if (a.isNotEmpty) paths.add(a);
    }
    for (final p in paths) {
      await SyncService.downloadFile(p);
    }
  }

  void _next() {
    _player.stop();
    _qaPlayer.stop();
    setState(() => _playingAllQa = false);
    if (_currentIndex < _sentences.length - 1) {
      setState(() {
        _currentIndex++;
        _showTranslation = false;
        _showQA = false;
        _audioLoaded = false;
        _audioDownloading = false;
        _audioUnavailable = false;
        _qaPlaying = false;
        _activeQaKey = null;
        _qaDownloading = false;
        _qaDownloadingKey = null;
      });
      _loadAudio(autoPlay: true);
    } else {
      // All done — reload a fresh batch
      _loadSentences();
    }
  }

  Future<void> _score(int score) async {
    if (_scoring) return;
    setState(() => _scoring = true);
    final item = _sentences[_currentIndex];
    final date = item['date'] as String? ?? '';
    final entryIndex = item['entry_index'] as int? ?? 0;

    // Save locally first — progress is never lost regardless of connectivity.
    int localId = 0;
    try {
      localId = await LocalDbService.saveSrsScore(
        date: date,
        entryIndex: entryIndex,
        score: score,
        synced: false,
      );
    } catch (_) {}

    // Advance immediately — don't wait for the network.
    setState(() => _scoring = false);
    _next();

    // Fire API in background; mark synced on success so it won't replay.
    final savedId = localId;
    ApiService.scoreEntry(date, entryIndex, score).then((_) {
      if (savedId > 0) LocalDbService.markScoreSynced(savedId);
    }).catchError((_) {
      // Will be replayed on next sync via _syncPendingScores().
    });
  }

  Widget _scoreButton(String label, int score, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: _scoring ? null : () => _score(score),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSentences,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sentences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'All caught up!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'No sentences due for review right now.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadSentences,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    final item = _sentences[_currentIndex];
    final sentence = item['sentence'] as String? ?? '';
    final inputSentence = item['input_language_sentence'] as String? ?? '';
    final outputTranslation = item['output_language_translation'] as String? ?? '';
    final tips = item['tips'] as String? ?? '';
    final qa = (item['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final reviewing = item['reviewing'] as Map<String, dynamic>? ?? {};
    final status = reviewing['status'] as String? ?? 'new';
    final date = (item['date'] as String? ?? '').replaceAll('/', '-');
    final title = item['title'] as String? ?? '';
    final remaining = _sentences.length - _currentIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sentence Review'),
        actions: [
          // Sync options popup
          _syncing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Sync audio',
                  onSelected: (value) {
                    if (value == 'current') _syncCurrentLessonAudio();
                    if (value == 'all') _syncAllAudio();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'current',
                      child: ListTile(
                        leading: Icon(Icons.audio_file_outlined),
                        title: Text('Sync current sentence'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'all',
                      child: ListTile(
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: Text(
                            'Sync all (${_sentences.length - _currentIndex} sentences)'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
          // Stats
          IconButton(
            tooltip: 'Stats & Streak',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$remaining left',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline mode banner
          if (_offlineMode)
            Material(
              color: Colors.orange.shade700,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline — showing cached review. Scores will sync when connected.',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Progress bar
          LinearProgressIndicator(
            value: _sentences.isEmpty
                ? 0
                : _currentIndex / _sentences.length,
            minHeight: 3,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date + title chip
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(date, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      if (title.isNotEmpty)
                        Chip(
                          label: Text(
                            title,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        label: Text(
                          status,
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: status == 'mastered'
                            ? Colors.green.shade100
                            : status == 'learning'
                                ? Colors.blue.shade100
                                : Colors.grey.shade100,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Main sentence card
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Audio playback row
                          Row(
                            children: [
                              if (_audioDownloading)
                                const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              else
                                IconButton(
                                  onPressed: _audioLoaded
                                      ? (_audioPlaying ? () => _player.stop() : _playAudio)
                                      : null,
                                  icon: Icon(
                                    _audioPlaying
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_outline,
                                    size: 32,
                                    color: _audioLoaded
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              if (_audioDownloading)
                                const Text(
                                  'Downloading audio…',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                )
                              else if (_audioUnavailable)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Audio unavailable',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    IconButton(
                                      onPressed: _loadAudio,
                                      icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                )
                              else if (!_audioLoaded)
                                const SizedBox.shrink(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Sentence
                          Text(
                            sentence.isNotEmpty ? sentence : inputSentence,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF3F51B5),
                            ),
                          ),

                          // Translation (revealed on tap)
                          if (_showTranslation) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            if (inputSentence.isNotEmpty &&
                                inputSentence != sentence)
                              Text(
                                inputSentence,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            if (outputTranslation.isNotEmpty &&
                                outputTranslation != sentence)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  outputTranslation,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.teal.shade700,
                                  ),
                                ),
                              ),
                            if (tips.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '💡 $tips',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Reveal / hide translation button
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _showTranslation = !_showTranslation),
                        icon: Icon(
                          _showTranslation
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                        ),
                        label: Text(_showTranslation
                            ? 'Hide translation'
                            : 'Show translation'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Q&A section
                  if (qa.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _showQA = !_showQA),
                            icon: Icon(
                              _showQA
                                  ? Icons.expand_less
                                  : Icons.quiz_outlined,
                              size: 16,
                            ),
                            label: Text(_showQA
                                ? 'Hide Q&A'
                                : 'Show Q&A (${qa.length} pairs)'),
                          ),
                        ),
                        if (_showQA) ...[
                          const SizedBox(width: 8),
                          // Play all Q&A in sequence
                          OutlinedButton.icon(
                            onPressed: () => _playAllQa(qa),
                            icon: Icon(
                              _playingAllQa
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline,
                              size: 16,
                              color: _playingAllQa
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            label: Text(
                              _playingAllQa ? 'Stop' : 'Play all',
                              style: TextStyle(
                                color: _playingAllQa
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_showQA)
                      Card(
                        color: Colors.grey.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: qa.asMap().entries.map((e) {
                              final idx = e.key;
                              final qaPair = e.value;
                              final question =
                                  qaPair['question'] as String? ?? '';
                              final answer = qaPair['answer'] as String? ?? '';
                              final questionInput =
                                  qaPair['question_input'] as String? ?? '';
                              final answerInput =
                                  qaPair['answer_input'] as String? ?? '';
                              final qAudioPath =
                                  qaPair['question_audio_path'] as String? ?? '';
                              final aAudioPath =
                                  qaPair['answer_audio_path'] as String? ?? '';

                              Widget qaPlayBtn(String type, String path) {
                                final key = '${idx}_$type';
                                final isActive = _activeQaKey == key;
                                final isLoading = _qaDownloading && _qaDownloadingKey == key;
                                if (path.isEmpty) return const SizedBox.shrink();
                                return GestureDetector(
                                  onTap: isLoading ? null : () => _playQaAudio(idx, type, path),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4, top: 2),
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 1.5),
                                          )
                                        : Icon(
                                            isActive && _qaPlaying
                                                ? Icons.stop_circle_outlined
                                                : Icons.play_circle_outline,
                                            size: 16,
                                            color: isActive && _qaPlaying
                                                ? Theme.of(context).colorScheme.primary
                                                : Colors.grey.shade500,
                                          ),
                                  ),
                                );
                              }

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        qaPlayBtn('q', qAudioPath),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                question,
                                                style: const TextStyle(
                                                  color: Color(0xFFE65100),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (questionInput.isNotEmpty)
                                                Text(
                                                  questionInput,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4, top: 2),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          qaPlayBtn('a', aAudioPath),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  answer,
                                                  style: const TextStyle(
                                                      color: Color(0xFF2E7D32)),
                                                ),
                                                if (answerInput.isNotEmpty)
                                                  Text(
                                                    answerInput,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey.shade500,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Score buttons (always visible at bottom)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'How well did you remember?',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _scoreButton('Again', 0, Colors.red),
                    _scoreButton('Hard', 2, Colors.orange),
                    _scoreButton('Good', 3, Colors.blue),
                    _scoreButton('Easy', 5, Colors.green),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _scoring ? null : _next,
                  child: const Text(
                    'Skip',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

/// A screen that shows native (input) text for each sentence first,
/// reveals translation and play button on tap, and for Q&A pairs
/// always shows input text, revealing translation and play on tap.
/// Includes download/sync and stats buttons (like review screen).
/// Uses same API, scoring, and navigation logic as SentencesScreen.
class NativeFirstSentencesScreen extends StatefulWidget {
  const NativeFirstSentencesScreen({super.key});

  @override
  State<NativeFirstSentencesScreen> createState() =>
      _NativeFirstSentencesScreenState();
}

class _NativeFirstSentencesScreenState
    extends State<NativeFirstSentencesScreen> {
  late TextEditingController _sentenceInputController;
  late List<TextEditingController> _qaQuestionControllers;
  late List<TextEditingController> _qaAnswerControllers;
  List<Map<String, dynamic>> _sentences = [];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;

  bool _showTranslation = false;
  final Set<int> _revealedQa = {}; // indices of Q&A pairs with translation revealed
  bool _scoring = false;
  bool _offlineMode = false;
  bool _syncing = false;

  // Keyboard navigation
  late FocusNode _sentenceFocusNode;
  late List<FocusNode> _qaQuestionFocusNodes;
  late List<FocusNode> _qaAnswerFocusNodes;

  // Font size control
  double _fontSizeScale = 1.0;

  static const _cacheKey = 'sentences_due_cache';

  late AudioPlayer _player;
  bool _audioLoaded = false;
  bool _audioPlaying = false;
  bool _audioDownloading = false;
  bool _audioUnavailable = false;

  late AudioPlayer _qaPlayer;
  bool _qaPlaying = false;
  String? _activeQaKey;
  bool _qaDownloading = false;
  String? _qaDownloadingKey;

  @override
  void initState() {
    super.initState();
    _sentenceInputController = TextEditingController();
    _qaQuestionControllers = [];
    _qaAnswerControllers = [];
    _sentenceFocusNode = FocusNode();
    _qaQuestionFocusNodes = [];
    _qaAnswerFocusNodes = [];
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      if (mounted) {
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
    _sentenceFocusNode.dispose();
    for (var node in _qaQuestionFocusNodes) {
      node.dispose();
    }
    for (var node in _qaAnswerFocusNodes) {
      node.dispose();
    }
    _player.dispose();
    _qaPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSentences() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Show cached data immediately for instant response.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        final cachedSentences =
            List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
        if (mounted && cachedSentences.isNotEmpty) {
          final qa = (cachedSentences[0]['qa'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          setState(() {
            _sentences = cachedSentences;
            _currentIndex = 0;
            _loading = false;
            _offlineMode = true; // assume offline until server confirms
            _qaQuestionControllers =
                List.generate(qa.length, (_) => TextEditingController());
            _qaAnswerControllers =
                List.generate(qa.length, (_) => TextEditingController());
            _qaQuestionFocusNodes =
                List.generate(qa.length, (_) => FocusNode());
            _qaAnswerFocusNodes =
                List.generate(qa.length, (_) => FocusNode());
          });
          _loadAudio(autoPlay: false);
        }
      } catch (_) {}
    }

    // Refresh from server in background.
    try {
      final sentences = await ApiService.getDueSentences(limit: 20);
      await prefs.setString(_cacheKey, jsonEncode(sentences));
      if (mounted) {
        final qa = sentences.isNotEmpty
            ? (sentences[0]['qa'] as List?)?.cast<Map<String, dynamic>>() ?? []
            : [];
        setState(() {
          _sentences = sentences;
          _currentIndex = 0;
          _loading = false;
          _offlineMode = false;
          _qaQuestionControllers =
              List.generate(qa.length, (_) => TextEditingController());
          _qaAnswerControllers =
              List.generate(qa.length, (_) => TextEditingController());
          _qaQuestionFocusNodes =
              List.generate(qa.length, (_) => FocusNode());
          _qaAnswerFocusNodes =
              List.generate(qa.length, (_) => FocusNode());
        });
        _loadAudio(autoPlay: false);
      }
    } catch (_) {
      if (mounted) {
        if (_sentences.isEmpty) {
          setState(() {
            _loading = false;
            _error =
                'Offline — sync the app when connected to load new sentences.';
          });
        } else {
          // Already showing cached data; just keep offline banner.
          setState(() => _loading = false);
        }
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
      final needsDownload = !kIsWeb && !File(await SyncService.localPath(audioPath)).existsSync();
      if (needsDownload) {
        setState(() { _audioDownloading = true; _audioLoaded = false; _audioUnavailable = false; });
      }
      final uri = await SyncService.ensureLocalAndGetUri(audioPath);
      if (!mounted) return;
      if (uri == null) {
        setState(() { _audioDownloading = false; _audioUnavailable = true; });
        return;
      }
      if (needsDownload) setState(() => _audioDownloading = false);
      await _player.setAudioSource(AudioSource.uri(uri));
      if (mounted) {
        setState(() {
          _audioLoaded = true;
          _audioUnavailable = false;
        });
        if (autoPlay) _player.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _audioLoaded = false;
          _audioDownloading = false;
          _audioUnavailable = true;
        });
      }
    }
  }

  void _playAudio() async {
    if (!_audioLoaded) {
      _loadAudio(autoPlay: true);
      return;
    }
    if (_qaPlaying) {
      await _qaPlayer.stop();
      setState(() {
        _qaPlaying = false;
        _activeQaKey = null;
      });
    }
    // Always seek to start when play is pressed (unless already playing)
    if (!_audioPlaying) {
      await _player.seek(Duration.zero);
    }
    _player.play();
  }

  Future<void> _playQaAudio(
      int pairIndex, String type, String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) return;
    final key = '${pairIndex}_$type';
    if (_activeQaKey == key && _qaPlaying) {
      await _qaPlayer.stop();
      setState(() {
        _qaPlaying = false;
        _activeQaKey = null;
      });
      return;
    }
    if (_audioPlaying) await _player.stop();

    // Always stop and reset before loading a different Q&A audio
    if (_qaPlaying) {
      await _qaPlayer.stop();
      // Wait a moment for the player to fully stop before loading new source
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final needsDownload = !kIsWeb && !File(await SyncService.localPath(audioPath)).existsSync();
      if (needsDownload) setState(() { _qaDownloading = true; _qaDownloadingKey = key; });
      final uri = await SyncService.ensureLocalAndGetUri(audioPath);
      if (!mounted) return;
      if (needsDownload) setState(() { _qaDownloading = false; _qaDownloadingKey = null; });
      if (uri == null) return;
      setState(() {
        _activeQaKey = key;
        _qaPlaying = true;
      });
      await _qaPlayer.setAudioSource(AudioSource.uri(uri));
      _qaPlayer.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _qaDownloading = false;
          _qaDownloadingKey = null;
        });
      }
    }
  }

  Future<void> _syncCurrentLessonAudio() async {
    if (_sentences.isEmpty || _syncing) return;
    setState(() => _syncing = true);
    final item = _sentences[_currentIndex];
    await _syncItemAudio(item);
    if (mounted) {
      setState(() => _syncing = false);
      _loadAudio();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Audio synced'), duration: Duration(seconds: 2)),
      );
    }
  }

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
    _sentenceInputController.clear();
    // Recreate controllers and focus nodes for Q&A fields based on new sentence's Q&A count
    final qa = (_sentences.length > _currentIndex + 1)
        ? (_sentences[_currentIndex + 1]['qa'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            []
        : <Map<String, dynamic>>[];
    _qaQuestionControllers =
        List.generate(qa.length, (_) => TextEditingController());
    _qaAnswerControllers =
        List.generate(qa.length, (_) => TextEditingController());
    // Dispose old focus nodes and create new ones
    for (var node in _qaQuestionFocusNodes) {
      node.dispose();
    }
    for (var node in _qaAnswerFocusNodes) {
      node.dispose();
    }
    _qaQuestionFocusNodes = List.generate(qa.length, (_) => FocusNode());
    _qaAnswerFocusNodes = List.generate(qa.length, (_) => FocusNode());
    setState(() {
      _revealedQa.clear();
      _showTranslation = false;
    });
    if (_currentIndex < _sentences.length - 1) {
      setState(() {
        _currentIndex++;
        _audioLoaded = false;
        _audioDownloading = false;
        _audioUnavailable = false;
        _qaPlaying = false;
        _activeQaKey = null;
        _qaDownloading = false;
        _qaDownloadingKey = null;
      });
      _loadAudio(autoPlay: false);
    } else {
      _loadSentences();
    }
  }

  Future<void> _score(int score) async {
    if (_scoring) return;
    setState(() => _scoring = true);
    final item = _sentences[_currentIndex];
    final date = item['date'] as String? ?? '';
    final entryIndex = item['entry_index'] as int? ?? 0;
    int localId = 0;
    try {
      localId = await LocalDbService.saveSrsScore(
        date: date,
        entryIndex: entryIndex,
        score: score,
        synced: false,
      );
    } catch (_) {}
    setState(() => _scoring = false);
    _next();
    final savedId = localId;
    ApiService.scoreEntry(date, entryIndex, score).then((_) {
      if (savedId > 0) LocalDbService.markScoreSynced(savedId);
    }).catchError((_) {});
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
              const Icon(Icons.check_circle_outline,
                  size: 64, color: Colors.green),
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
    final inputSentence = item['input_language_sentence'] as String? ?? '';
    final outputTranslation =
        item['output_language_translation'] as String? ?? '';
    final sentence = item['sentence'] as String? ?? '';
    final tips = item['tips'] as String? ?? '';
    final qa = (item['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final reviewing = item['reviewing'] as Map<String, dynamic>? ?? {};
    final status = reviewing['status'] as String? ?? 'new';
    final date = (item['date'] as String? ?? '').replaceAll('/', '-');
    final title = item['title'] as String? ?? '';
    final remaining = _sentences.length - _currentIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation Excercise'),
        actions: [
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
          IconButton(
            tooltip: 'Stats & Streak',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          PopupMenuButton<double>(
            tooltip: 'Font size',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  'Tt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            onSelected: (scale) {
              setState(() => _fontSizeScale = scale);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 0.8,
                child: Row(
                  children: [
                    const Text('Small'),
                    if (_fontSizeScale <= 0.9)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1.0,
                child: Row(
                  children: [
                    const Text('Normal'),
                    if (_fontSizeScale > 0.9 && _fontSizeScale <= 1.1)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1.3,
                child: Row(
                  children: [
                    const Text('Large'),
                    if (_fontSizeScale > 1.1 && _fontSizeScale <= 1.5)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1.7,
                child: Row(
                  children: [
                    const Text('Extra Large'),
                    if (_fontSizeScale > 1.5)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),
            ],
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
          LinearProgressIndicator(
            value: _sentences.isEmpty ? 0 : _currentIndex / _sentences.length,
            minHeight: 3,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  // Main sentence card: always show input, reveal translation/play on tap
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconButton(
                            icon: Icon(
                              _showTranslation ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _showTranslation = !_showTranslation),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minHeight: 0,
                              minWidth: 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    IconButton(
                                      onPressed: _audioLoaded
                                          ? (_audioPlaying
                                              ? () => _player.stop()
                                              : _playAudio)
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
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            inputSentence,
                                            style: TextStyle(
                                              fontSize: 18 * _fontSizeScale,
                                              fontWeight: FontWeight.w500,
                                              color: const Color(0xFF3F51B5),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _sentenceInputController,
                                            focusNode: _sentenceFocusNode,
                                            decoration: InputDecoration(
                                              labelText: 'Your translation attempt (press Enter to reveal)',
                                              labelStyle: TextStyle(fontSize: 14 * _fontSizeScale),
                                              border: const OutlineInputBorder(),
                                            ),
                                            style: TextStyle(fontSize: 16 * _fontSizeScale),
                                            minLines: 1,
                                            maxLines: 1,
                                            textInputAction: TextInputAction.done,
                                            onSubmitted: (_) => setState(() => _showTranslation = !_showTranslation),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (_showTranslation) ...[
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  if (sentence.isNotEmpty &&
                                      sentence != inputSentence)
                                    Text(
                                      sentence,
                                      style: TextStyle(
                                        fontSize: 14 * _fontSizeScale,
                                        color: Colors.grey.shade700,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  if (outputTranslation.isNotEmpty &&
                                      outputTranslation != inputSentence)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        outputTranslation,
                                        style: TextStyle(
                                          fontSize: 14 * _fontSizeScale,
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
                                  Row(
                                    children: [
                                      if (_audioDownloading)
                                        const SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          onPressed: _audioLoaded
                                              ? (_audioPlaying
                                                  ? () => _player.stop()
                                                  : _playAudio)
                                              : null,
                                          icon: Icon(
                                            _audioPlaying
                                                ? Icons.stop_circle_outlined
                                                : Icons.play_circle_outline,
                                            size: 32,
                                            color: _audioLoaded
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                      if (_audioDownloading)
                                        const Text(
                                          'Downloading audio…',
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.grey),
                                        )
                                      else if (_audioUnavailable)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'Audio unavailable',
                                              style: TextStyle(
                                                  fontSize: 11, color: Colors.grey),
                                            ),
                                            IconButton(
                                              onPressed: _loadAudio,
                                              icon: const Icon(Icons.refresh,
                                                  size: 16, color: Colors.grey),
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
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Q&A section: always show input, reveal translation/play on tap
                  if (qa.isNotEmpty)
                    Card(
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: qa.asMap().entries.map((e) {
                            final idx = e.key;
                            final qaPair = e.value;
                            final questionInput =
                                qaPair['question_input'] as String? ?? '';
                            final answerInput =
                                qaPair['answer_input'] as String? ?? '';
                            final question =
                                qaPair['question'] as String? ?? '';
                            final answer = qaPair['answer'] as String? ?? '';
                            final qAudioPath =
                                qaPair['question_audio_path'] as String? ?? '';
                            final aAudioPath =
                                qaPair['answer_audio_path'] as String? ?? '';
                            final revealed = _revealedQa.contains(idx);
                            Widget qaPlayBtn(String type, String path) {
                              final key = '${idx}_$type';
                              final isActive = _activeQaKey == key;
                              final isLoading =
                                  _qaDownloading && _qaDownloadingKey == key;
                              if (path.isEmpty) return const SizedBox.shrink();
                              return GestureDetector(
                                onTap: isLoading
                                    ? null
                                    : () => _playQaAudio(idx, type, path),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4, top: 2),
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 1.5),
                                        )
                                      : Icon(
                                          isActive && _qaPlaying
                                              ? Icons.stop_circle_outlined
                                              : Icons.play_circle_outline,
                                          size: 16,
                                          color: isActive && _qaPlaying
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Colors.grey.shade500,
                                        ),
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      revealed
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() {
                                      if (revealed) {
                                        _revealedQa.remove(idx);
                                      } else {
                                        _revealedQa.add(idx);
                                      }
                                    }),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minHeight: 0,
                                      minWidth: 0,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (revealed)
                                              qaPlayBtn('q', qAudioPath),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        questionInput,
                                                        style: TextStyle(
                                                          fontSize: 14 * _fontSizeScale,
                                                          color: const Color(0xFFE65100),
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      TextField(
                                                       controller:
                                                           _qaQuestionControllers[idx],
                                                       focusNode:
                                                           _qaQuestionFocusNodes[idx],
                                                       decoration: InputDecoration(
                                                         labelText:
                                                             'Your translation attempt',
                                                         labelStyle: TextStyle(
                                                             fontSize: 12 *
                                                                 _fontSizeScale),
                                                         border:
                                                             const OutlineInputBorder(),
                                                       ),
                                                       style: TextStyle(
                                                           fontSize:
                                                               14 * _fontSizeScale),
                                                       minLines: 1,
                                                       maxLines: 1,
                                                       textInputAction: TextInputAction.next,
                                                       onSubmitted: (_) => _qaAnswerFocusNodes[idx].requestFocus(),
                                                      ),
                                                    ],
                                                  ),
                                                  if (revealed &&
                                                      question.isNotEmpty)
                                                    Text(
                                                      question,
                                                      style: TextStyle(
                                                        fontSize: 11 * _fontSizeScale,
                                                        color: Colors
                                                            .grey.shade500,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            // Removed right play button for Q row
                                          ],
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 4, top: 2),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (revealed)
                                                qaPlayBtn('a', aAudioPath),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          answerInput,
                                                          style: TextStyle(
                                                              fontSize: 14 * _fontSizeScale,
                                                              color: const Color(
                                                                  0xFF2E7D32)),
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        TextField(
                                                          controller:
                                                              _qaAnswerControllers[
                                                                  idx],
                                                          focusNode:
                                                              _qaAnswerFocusNodes[
                                                                  idx],
                                                          decoration:
                                                              InputDecoration(
                                                            labelText:
                                                                'Your translation attempt',
                                                            labelStyle: TextStyle(
                                                                fontSize: 12 *
                                                                    _fontSizeScale),
                                                            border:
                                                                const OutlineInputBorder(),
                                                          ),
                                                          style: TextStyle(
                                                              fontSize: 14 *
                                                                  _fontSizeScale),
                                                          minLines: 1,
                                                          maxLines: 1,
                                                          textInputAction: TextInputAction.done,
                                                          onSubmitted: (_) => setState(() {
                                                            if (_revealedQa.contains(idx)) {
                                                              _revealedQa.remove(idx);
                                                            } else {
                                                              _revealedQa.add(idx);
                                                            }
                                                          }),
                                                        ),
                                                      ],
                                                    ),
                                                    if (revealed &&
                                                        answer.isNotEmpty)
                                                      Text(
                                                        answer,
                                                        style: TextStyle(
                                                          fontSize: 11 * _fontSizeScale,
                                                          color: Colors
                                                              .grey.shade500,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              // Removed right play button for A row
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
              ),
            ),
          ),
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

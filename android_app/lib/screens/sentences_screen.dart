import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../services/sync_service.dart';

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
    });
    try {
      final sentences = await ApiService.getDueSentences(limit: 20);
      if (mounted) {
        setState(() {
          _sentences = sentences;
          _currentIndex = 0;
          _loading = false;
        });
        _loadAudio(autoPlay: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
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
      final localFile = await SyncService.localPath(audioPath);
      if (!File(localFile).existsSync()) {
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
      await _player.setAudioSource(AudioSource.uri(Uri.file(localFile)));
      if (mounted) {
        setState(() { _audioLoaded = true; _audioUnavailable = false; });
        if (autoPlay) _player.play();
      }
    } catch (_) {
      if (mounted) setState(() { _audioLoaded = false; _audioDownloading = false; _audioUnavailable = true; });
    }
  }

  void _playAudio() async {
    if (!_audioLoaded) return;
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
      final localFile = await SyncService.localPath(audioPath);
      if (!File(localFile).existsSync()) {
        setState(() { _qaDownloading = true; _qaDownloadingKey = key; });
        final ok = await SyncService.downloadFile(audioPath);
        if (!mounted) return;
        setState(() { _qaDownloading = false; _qaDownloadingKey = null; });
        if (!ok) return;
      }
      setState(() { _activeQaKey = key; _qaPlaying = true; });
      await _qaPlayer.setAudioSource(AudioSource.uri(Uri.file(localFile)));
      _qaPlayer.play();
    } catch (_) {
      if (mounted) setState(() { _qaDownloading = false; _qaDownloadingKey = null; });
    }
  }

  void _next() {
    _player.stop();
    _qaPlayer.stop();
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
    try {
      await ApiService.scoreEntry(
        item['date'] as String,
        item['entry_index'] as int,
        score,
      );
    } catch (_) {
      // Non-fatal — we'll still advance
    }
    setState(() => _scoring = false);
    _next();
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

                  // Reveal translation button
                  if (!_showTranslation)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _showTranslation = true),
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('Show translation'),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Q&A section
                  if (qa.isNotEmpty) ...[
                    if (!_showQA)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _showQA = true),
                          icon: const Icon(Icons.quiz_outlined, size: 16),
                          label: Text('Show Q&A (${qa.length} pairs)'),
                        ),
                      )
                    else
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
                                              if (_showTranslation &&
                                                  questionInput.isNotEmpty)
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
                                                if (_showTranslation &&
                                                    answerInput.isNotEmpty)
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

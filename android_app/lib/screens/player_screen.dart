import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../services/sync_service.dart';

/// Synthetic tab name for the "Input Diary" view (no audio).
const _kInputDiaryTab = 'Input Diary';

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

  /// All tab names: TPRS variants + synthetic "Input Diary" at the end.
  late List<String> _tabNames;
  late String _currentTab;
  late Map<String, dynamic> _variants;

  // TPRS rendering keywords
  String _kwSentence = 'SETNING:';
  String _kwQuestion = 'SPØRSMÅL:';
  String _kwAnswer = 'SVAR:';

  // Input Diary state
  String _diaryContent = '';
  bool _diaryLoading = false;
  String? _lessonDate; // YYYY-MM-DD extracted from base name

  // Font size
  double _fontSize = 14.0;
  static const List<double> _fontSizes = [12.0, 14.0, 16.0, 20.0];

  // Loop
  bool _loopEnabled = false;

  // Sentence timing + highlighting
  List<Map<String, dynamic>> _sentenceEntries = [];
  int _activeSentenceIndex = -1;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _sentenceKeys = {};

  // Translation toggle — set of entry indices whose translation is revealed
  final Set<int> _expandedTranslations = {};

  // Scoring state
  int? _scoredSentenceIndex;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _variants = widget.lesson['variants'] as Map<String, dynamic>? ?? {};
    _tabNames = [..._variants.keys, _kInputDiaryTab];
    _currentTab = _tabNames.isNotEmpty ? _tabNames.first : _kInputDiaryTab;

    // Extract YYYY-MM-DD from base name (e.g. …_TPRS_2026-01-21_…)
    final base = widget.lesson['base'] as String? ?? '';
    final m = RegExp(r'_TPRS_(\d{4}-\d{2}-\d{2})').firstMatch(base);
    _lessonDate = m?.group(1);

    _loadKeywords().then((_) {
      if (_currentTab != _kInputDiaryTab) {
        _loadVariant(_currentTab);
      } else {
        _loadDiaryContent();
      }
    });

    SyncManager.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (!SyncManager.instance.isSyncing && mounted) {
      if (_currentTab != _kInputDiaryTab) {
        _loadVariant(_currentTab);
      } else {
        _loadDiaryContent();
      }
    }
  }

  Future<void> _loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _kwSentence = prefs.getString('tprs_sentence') ?? 'SETNING:';
      _kwQuestion = prefs.getString('tprs_question') ?? 'SPØRSMÅL:';
      _kwAnswer = prefs.getString('tprs_answer') ?? 'SVAR:';
      _fontSize = prefs.getDouble('player_font_size') ?? 14.0;
    });
  }

  void _cycleFontSize() async {
    final idx = _fontSizes.indexOf(_fontSize);
    final next = _fontSizes[(idx + 1) % _fontSizes.length];
    setState(() => _fontSize = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_font_size', next);
  }

  void _toggleLoop() {
    setState(() => _loopEnabled = !_loopEnabled);
    _player.setLoopMode(_loopEnabled ? LoopMode.one : LoopMode.off);
  }

  Future<void> _loadVariant(String variantName) async {
    if (variantName.isEmpty || variantName == _kInputDiaryTab) return;
    final filename = _variants[variantName] as String? ?? '';
    final mp3Path = await SyncService.localPath('TPRS/$filename');
    final mdPath =
        mp3Path.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '.md');

    await _player.stop();
    setState(() {
      _audioReady = false;
      _markdownContent = '';
      _sentenceEntries = [];
      _expandedTranslations.clear();
      _activeSentenceIndex = -1;
      _sentenceKeys.clear();
    });

    final audioFile = File(mp3Path);
    if (await audioFile.exists()) {
      try {
        await _player.setFilePath(mp3Path);
      } catch (_) {}
      if (mounted) {
        setState(() => _audioReady = true);
        _startPositionListener();
      }
    }

    final mdFile = File(mdPath);
    if (await mdFile.exists()) {
      final content = mdFile.readAsStringSync();
      if (mounted) setState(() => _markdownContent = content);
    }

    // Fetch structured entries (timings + translations) from server
    if (_lessonDate != null) {
      try {
        final variantKey = _variantToApiKey(variantName);
        final data = await ApiService.getLessonEntries(_lessonDate!, variantKey);
        final entries =
            (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) {
          setState(() {
            _sentenceEntries = entries;
            _expandedTranslations.clear();
            _activeSentenceIndex = -1;
            _sentenceKeys.clear();
            for (var i = 0; i < entries.length; i++) {
              _sentenceKeys[i] = GlobalKey();
            }
          });
        }
      } catch (_) {
        // Server unreachable — fall back to markdown-only display
      }
    }
  }

  String _variantToApiKey(String variantName) {
    return variantName.toLowerCase();
  }

  void _startPositionListener() {
    _player.positionStream.listen((pos) {
      if (!mounted || _sentenceEntries.isEmpty) return;
      final ms = pos.inMilliseconds;
      int idx = -1;
      for (var i = 0; i < _sentenceEntries.length; i++) {
        final timing =
            _sentenceEntries[i]['audio_timing'] as Map<String, dynamic>?;
        if (timing == null) continue;
        final start = (timing['start_ms'] as int?) ?? 0;
        final end = (timing['end_ms'] as int?) ?? 0;
        if (end > start && ms >= start && ms < end) {
          idx = i;
          break;
        }
      }
      if (idx != _activeSentenceIndex) {
        setState(() => _activeSentenceIndex = idx);
        if (idx >= 0) _scrollToSentence(idx);
      }
    });
  }

  void _scrollToSentence(int idx) {
    final key = _sentenceKeys[idx];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
  }

  /// Load the Input Diary content: try local cache first, then server.
  Future<void> _loadDiaryContent() async {
    if (_lessonDate == null) {
      setState(() => _diaryContent = '(No date found in lesson name)');
      return;
    }
    final base = widget.lesson['base'] as String? ?? '';
    final cachePath = await SyncService.localPath('TPRS/$base.diary_input.txt');
    final cacheFile = File(cachePath);

    if (await cacheFile.exists()) {
      setState(() => _diaryContent = cacheFile.readAsStringSync());
      return;
    }

    // Not cached — fetch from server
    setState(() {
      _diaryLoading = true;
      _diaryContent = '';
    });
    try {
      final content = await ApiService.getDiaryEntryByDate(_lessonDate!);
      if (content.isNotEmpty) {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(content);
      }
      if (mounted) setState(() => _diaryContent = content);
    } catch (e) {
      if (mounted) {
        setState(() => _diaryContent =
            'Could not load diary entry.\nTap sync or check server connection.\n\nError: $e');
      }
    } finally {
      if (mounted) setState(() => _diaryLoading = false);
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
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── TPRS renderer ─────────────────────────────────────────────────────────────

  Widget _buildTprsContent() {
    if (_sentenceEntries.isNotEmpty) {
      return _buildStructuredContent();
    }
    if (_markdownContent.isEmpty) {
      return const Center(child: Text('No content — tap Sync to download.'));
    }
    return _buildMarkdownFallback();
  }

  Widget _buildStructuredContent() {
    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _sentenceEntries.length,
        itemBuilder: (ctx, i) {
          final entry = _sentenceEntries[i];
          final isActive = i == _activeSentenceIndex;
          final isExpanded = _expandedTranslations.contains(i);
          final isScored = i == _scoredSentenceIndex;
          final sentence = entry['sentence'] as String? ?? '';
          final inputSentence =
              entry['input_language_sentence'] as String? ?? '';
          final outputTranslation =
              entry['output_language_translation'] as String? ?? '';
          final qa =
              (entry['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];

          return Container(
            key: _sentenceKeys[i],
            margin: const EdgeInsets.only(bottom: 16),
            decoration: isActive
                ? BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sentence row — tap to toggle translation
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedTranslations.remove(i);
                      } else {
                        _expandedTranslations.add(i);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            sentence.isNotEmpty ? sentence : inputSentence,
                            style: TextStyle(
                              color: const Color(0xFF3F51B5),
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: _fontSize + 1,
                            ),
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                        if (isScored) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check_circle,
                              size: 14, color: Colors.green.shade400),
                        ],
                      ],
                    ),
                  ),
                ),

                // Translation (hidden until tapped)
                if (isExpanded &&
                    (inputSentence.isNotEmpty ||
                        outputTranslation.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inputSentence.isNotEmpty)
                          Text(
                            inputSentence,
                            style: TextStyle(
                              fontSize: _fontSize - 1,
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (outputTranslation.isNotEmpty &&
                            outputTranslation != sentence)
                          Text(
                            outputTranslation,
                            style: TextStyle(
                              fontSize: _fontSize - 1,
                              color: Colors.teal.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),

                // Q&A pairs
                ...qa.map((qaPair) {
                  final question = qaPair['question'] as String? ?? '';
                  final answer = qaPair['answer'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_kwQuestion $question',
                          style: TextStyle(
                            color: const Color(0xFFE65100),
                            fontWeight: FontWeight.bold,
                            fontSize: _fontSize,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            '$_kwAnswer $answer',
                            style: TextStyle(
                              color: const Color(0xFF2E7D32),
                              fontSize: _fontSize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarkdownFallback() {
    final blocks = _markdownContent.split(RegExp(r'\n{2,}'));
    final blockWidgets = <Widget>[];

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.trim().split('\n');
      final lineWidgets = <Widget>[];
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        lineWidgets.add(_buildTprsLine(line));
      }
      if (lineWidgets.isNotEmpty) {
        blockWidgets.add(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lineWidgets,
        ));
        blockWidgets.add(const SizedBox(height: 16));
      }
    }

    return SelectionArea(
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: blockWidgets,
      ),
    );
  }

  Widget _buildTprsLine(String line) {
    if (line.startsWith(_kwSentence)) {
      final text = line.substring(_kwSentence.length).trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '$_kwSentence $text',
          style: TextStyle(
              color: const Color(0xFF3F51B5),
              fontWeight: FontWeight.bold,
              fontSize: _fontSize + 1),
        ),
      );
    } else if (line.startsWith(_kwQuestion)) {
      final text = line.substring(_kwQuestion.length).trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 2, top: 4),
        child: Text(
          '$_kwQuestion $text',
          style: TextStyle(
              color: const Color(0xFFE65100),
              fontWeight: FontWeight.bold,
              fontSize: _fontSize),
        ),
      );
    } else if (line.startsWith(_kwAnswer)) {
      final text = line.substring(_kwAnswer.length).trim();
      return Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(
          '$_kwAnswer $text',
          style: TextStyle(color: const Color(0xFF2E7D32), fontSize: _fontSize),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(line,
            style: TextStyle(color: Colors.grey, fontSize: _fontSize - 1)),
      );
    }
  }

  // ── Scoring bar ───────────────────────────────────────────────────────────────

  Widget _buildScoringBar() {
    final total = _sentenceEntries.length;
    final current = _activeSentenceIndex + 1;
    final buttons = <Map<String, dynamic>>[
      {'label': 'Again', 'score': 0, 'color': Colors.red},
      {'label': 'Hard', 'score': 2, 'color': Colors.orange},
      {'label': 'Good', 'score': 3, 'color': Colors.blue},
      {'label': 'Easy', 'score': 5, 'color': Colors.green},
    ];
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            '$current/$total',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          ...buttons.map((t) {
            final label = t['label'] as String;
            final score = t['score'] as int;
            final color = t['color'] as Color;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _scoreEntry(_activeSentenceIndex, score),
                  child: Text(label),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _scoreEntry(int entryIndex, int score) async {
    if (_lessonDate == null) return;
    final entry = _sentenceEntries[entryIndex];
    final idx = (entry['index'] as int?) ?? entryIndex;

    setState(() => _scoredSentenceIndex = entryIndex);

    try {
      final result = await ApiService.scoreEntry(_lessonDate!, idx, score);
      final reviewing = result['reviewing'] as Map<String, dynamic>?;
      final nextReview = reviewing?['next_review']; // ignore: unused_local_variable
      final intervalDays = reviewing?['interval_days'] as int?;

      await LocalDbService.saveSrsScore(
        date: _lessonDate!,
        entryIndex: idx,
        score: score,
      );

      if (mounted) {
        const scoreLabels = ['Again', '', 'Hard', 'Good', '', 'Easy'];
        final scoreLabel =
            score < scoreLabels.length ? scoreLabels[score] : '$score';
        final days =
            intervalDays != null ? ' — next in $intervalDays days' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked $scoreLabel$days'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Save locally even when server is unreachable
      try {
        await LocalDbService.saveSrsScore(
          date: _lessonDate!,
          entryIndex: idx,
          score: score,
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Score saved locally (server unreachable)'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ── Input Diary renderer ──────────────────────────────────────────────────────

  Widget _buildDiaryContent() {
    if (_diaryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_diaryContent.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _lessonDate == null
                  ? 'No date found in lesson name.'
                  : 'No diary entry found for $_lessonDate.\nMake sure the server has this entry.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Markdown(
      data: _diaryContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: _fontSize, color: Colors.black87),
        h2: TextStyle(
            fontSize: _fontSize + 4,
            fontWeight: FontWeight.bold,
            color: Colors.black87),
        h3: TextStyle(
            fontSize: _fontSize + 2,
            fontWeight: FontWeight.bold,
            color: Colors.black54),
        strong: TextStyle(
            fontWeight: FontWeight.bold, color: const Color(0xFF3F51B5)),
        em: TextStyle(
            fontStyle: FontStyle.italic, color: Colors.grey.shade700),
        blockquoteDecoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      padding: const EdgeInsets.all(16),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.lesson['display'] as String? ?? '';
    final isInputDiary = _currentTab == _kInputDiaryTab;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          // Font size cycle button
          IconButton(
            tooltip: 'Font size (${_fontSize.toStringAsFixed(0)})',
            icon: const Icon(Icons.text_fields),
            onPressed: _cycleFontSize,
          ),
          // Loop toggle
          IconButton(
            tooltip: _loopEnabled ? 'Loop: on' : 'Loop: off',
            icon: Icon(
              _loopEnabled ? Icons.repeat_one : Icons.repeat,
              color: _loopEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: _toggleLoop,
          ),
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
          // ── Sync progress bar (visible while syncing) ─────────────────────
          ListenableBuilder(
            listenable: SyncManager.instance,
            builder: (_, __) {
              final sync = SyncManager.instance;
              if (!sync.isSyncing) return const SizedBox.shrink();
              return Container(
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
                            minHeight: 4,
                          ),
                          const SizedBox(height: 2),
                          Text(sync.message,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis),
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
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    const SizedBox(width: 4),
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
              );
            },
          ),
          // ── Tab / Variant selector ────────────────────────────────────────
          if (_tabNames.length > 1)
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: _tabNames.map((v) {
                    return ButtonSegment<String>(
                      value: v,
                      label: Text(v, style: const TextStyle(fontSize: 12)),
                      icon: v == _kInputDiaryTab
                          ? const Icon(Icons.menu_book_outlined, size: 14)
                          : null,
                    );
                  }).toList(),
                  selected: {_currentTab},
                  onSelectionChanged: (sel) {
                    final tab = sel.first;
                    setState(() {
                      _currentTab = tab;
                      _audioReady = false;
                    });
                    if (tab == _kInputDiaryTab) {
                      _player.stop();
                      _loadDiaryContent();
                    } else {
                      _loadVariant(tab);
                    }
                  },
                ),
              ),
            ),

          // ── Audio controls (hidden for Input Diary tab) ───────────────────
          if (!isInputDiary)
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
                              ? position.inMilliseconds /
                                  duration.inMilliseconds
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
                            ? () => _player.seek(_player.position -
                                const Duration(seconds: 10))
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
                            ? () => _player.seek(_player.position +
                                const Duration(seconds: 10))
                            : null,
                      ),
                    ],
                  ),
                  if (!_audioReady)
                    const Text(
                        'Audio not synced yet — tap ⟳ in the toolbar.',
                        style:
                            TextStyle(color: Colors.orange, fontSize: 12)),
                ],
              ),
            ),

          // ── Scoring bar (visible when a sentence is active and structured data loaded) ──
          if (_activeSentenceIndex >= 0 && _sentenceEntries.isNotEmpty)
            _buildScoringBar(),

          // ── Content area ──────────────────────────────────────────────────
          Expanded(
            child: isInputDiary
                ? _buildDiaryContent()
                : _buildTprsContent(),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
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
  /// Safe int coercion: handles JSON values that may arrive as double (e.g.
  /// audio_timing.start_ms / end_ms were stored as floats in older diary.json
  /// files produced by audio_timing.py before the int-cast fix).
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.round();
    return 0;
  }

  late final AudioPlayer _player;
  bool _audioReady = false;
  StreamSubscription<Duration>? _positionSub;

  /// All tab names: TPRS variants + synthetic "Input Diary" at the end.
  late List<String> _tabNames;
  late String _currentTab;
  late Map<String, dynamic> _variants;
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
  // Block repeat
  bool _loopBlock = false;

  // Sentence timing + highlighting
  List<Map<String, dynamic>> _sentenceEntries = [];
  // Flat list of timed segments: {entryIdx, qaIdx (-1=sentence), isQuestion, timing}
  List<Map<String, dynamic>> _segments = [];
  // Entry-level spans covering the full block (sentence → last answer)
  Map<int, Map<String, int>> _entrySpans = {};
  int _activeEntryIndex = -1;
  int _activeQaIndex = -1; // -1 = sentence is active
  bool _activeIsQuestion = false;
  // Sticky: keep last Q/A highlighted during inter-segment pauses
  int _stickyQaIndex = -1;
  bool _stickyIsQuestion = false;
  int _stickyEntryIndex = -1;
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
      // After sync completes: only try to load audio if it wasn't ready.
      // Never reload or clear entries — they are still valid from the initial load.
      if (_currentTab != _kInputDiaryTab && !_audioReady) {
        _tryLoadAudio(_currentTab);
      }
    }
  }

  /// Attempt to load audio for [variantName] without touching text entries.
  Future<void> _tryLoadAudio(String variantName) async {
    if (variantName.isEmpty || variantName == _kInputDiaryTab) return;
    final filename = _variants[variantName] as String? ?? '';
    if (filename.isEmpty) return;
    final mp3Path = await SyncService.localPath('TPRS/$filename');
    final audioFile = File(mp3Path);
    if (!await audioFile.exists()) return;

    bool audioSet = false;
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.file(mp3Path)));
      audioSet = true;
    } catch (_) {}
    if (audioSet && mounted) {
      setState(() => _audioReady = true);
      _startPositionListener();
    }
  }

  Future<void> _loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
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

    await _player.stop();
    setState(() {
      _audioReady = false;
      _activeEntryIndex = -1;
      _activeQaIndex = -1;
      _activeIsQuestion = false;
      _stickyQaIndex = -1;
      _stickyIsQuestion = false;
      _stickyEntryIndex = -1;
    });

    // Load audio (best-effort — file may not be synced yet).
    await _tryLoadAudio(variantName);

    // Fetch structured entries (timings + translations) from server.
    if (_lessonDate != null && _sentenceEntries.isEmpty) {
      final variantKey = _variantToApiKey(variantName);
      bool loaded = false;
      try {
        final data = await ApiService.getLessonEntries(_lessonDate!, variantKey);
        final entries =
            (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted && entries.isNotEmpty) {
          _applyEntries(entries);
          loaded = true;
        }
      } catch (_) {
        // Server unreachable — try local diary.json cache
      }

      if (!loaded) {
        await _loadEntriesFromLocalJson(variantKey);
      }
    }
  }

  /// Parse entries for [variantKey] from the locally cached diary.json.
  Future<void> _loadEntriesFromLocalJson(String variantKey) async {
    if (_lessonDate == null) return;
    try {
      final jsonPath = await SyncService.localPath('diary.json');
      final jsonFile = File(jsonPath);
      if (!await jsonFile.exists()) return;

      final data = json.decode(await jsonFile.readAsString()) as Map<String, dynamic>;
      final diaries = (data['diaries'] as List?) ?? [];

      // diary.json dates are stored as YYYY/MM/DD; _lessonDate is YYYY-MM-DD
      final lessonDateSlash = _lessonDate!.replaceAll('-', '/');
      Map<String, dynamic>? day;
      for (final d in diaries) {
        if ((d as Map<String, dynamic>)['date'] == lessonDateSlash) {
          day = d;
          break;
        }
      }
      if (day == null) return;

      final rawEntries = (day['entries'] as List?) ?? [];
      final entries = rawEntries.map((e) {
        final em = e as Map<String, dynamic>;
        final lesson = (em['lessons'] as Map<String, dynamic>?)?[variantKey]
            as Map<String, dynamic>? ?? {};
        return <String, dynamic>{
          'sentence': lesson['sentence'] ?? '',
          'input_language_sentence': em['input_language_sentence'] ?? '',
          'output_language_translation': em['output_language_translation'] ?? '',
          'audio_timing': lesson['audio_timing'],
          'qa': lesson['qa'] ?? [],
        };
      }).cast<Map<String, dynamic>>().toList();

      if (mounted && entries.isNotEmpty) {
        _applyEntries(entries);
      }
    } catch (e, st) {
      // Corrupt or missing local cache — show nothing (error logged for debugging)
      debugPrint('_loadEntriesFromLocalJson error: $e\n$st');
    }
  }

  void _applyEntries(List<Map<String, dynamic>> entries) {
    setState(() {
      _sentenceEntries = entries;
      _expandedTranslations.clear();
      _activeEntryIndex = -1;
      _activeQaIndex = -1;
      _activeIsQuestion = false;
      _sentenceKeys.clear();
      for (var i = 0; i < entries.length; i++) {
        _sentenceKeys[i] = GlobalKey();
      }
    });
    _buildSegmentList();
  }

  String _variantToApiKey(String variantName) {
    return variantName.toLowerCase();
  }

  void _buildSegmentList() {
    final segs = <Map<String, dynamic>>[];
    final spans = <int, Map<String, int>>{}; // entryIdx → {start, end}

    for (var i = 0; i < _sentenceEntries.length; i++) {
      final entry = _sentenceEntries[i];
      final st = entry['audio_timing'] as Map<String, dynamic>?;
      int blockStart = _toInt(st?['start_ms']);
      int blockEnd = _toInt(st?['end_ms']);

      if (st != null && blockEnd > 0) {
        segs.add({'entryIdx': i, 'qaIdx': -1, 'isQuestion': false, 'timing': st});
      }
      final qa = (entry['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (var j = 0; j < qa.length; j++) {
        final qt = qa[j]['question_timing'] as Map<String, dynamic>?;
        if (qt != null && _toInt(qt['end_ms']) > 0) {
          segs.add({'entryIdx': i, 'qaIdx': j, 'isQuestion': true, 'timing': qt});
          final end = _toInt(qt['end_ms']);
          if (end > blockEnd) blockEnd = end;
        }
        final at = qa[j]['answer_timing'] as Map<String, dynamic>?;
        if (at != null && _toInt(at['end_ms']) > 0) {
          segs.add({'entryIdx': i, 'qaIdx': j, 'isQuestion': false, 'timing': at});
          final end = _toInt(at['end_ms']);
          if (end > blockEnd) blockEnd = end;
        }
      }
      if (blockEnd > 0) spans[i] = {'start': blockStart, 'end': blockEnd};
    }
    _segments = segs;
    _entrySpans = spans;
  }

  void _startPositionListener() {
    _positionSub?.cancel();
    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      final ms = pos.inMilliseconds;

      // Block repeat: if enabled, loop the current active entry block
      if (_loopBlock && _activeEntryIndex >= 0) {
        final span = _entrySpans[_activeEntryIndex];
        if (span != null && ms >= span['end']!) {
          _player.seek(Duration(milliseconds: span['start']!));
          return;
        }
      }

      // Container highlight: based on full entry block span (stays on during pauses)
      int entryIdx = -1;
      for (final e in _entrySpans.entries) {
        if (ms >= e.value['start']! && ms < e.value['end']!) {
          entryIdx = e.key;
          break;
        }
      }

      // Fine-grained: which specific segment (sentence/Q/A) is playing
      int qaIdx = -1;
      bool isQ = false;
      for (final seg in _segments) {
        final t = seg['timing'] as Map<String, dynamic>;
        final start = _toInt(t['start_ms']);
        final end = _toInt(t['end_ms']);
        if (end > start && ms >= start && ms < end) {
          qaIdx = seg['qaIdx'] as int;
          isQ = seg['isQuestion'] as bool;
          break;
        }
      }

      // Sticky: during pauses between Q/A segments, keep the last Q/A highlighted
      // instead of reverting to the sentence.
      if (qaIdx >= 0) {
        // A real segment is active — update sticky state
        _stickyQaIndex = qaIdx;
        _stickyIsQuestion = isQ;
        _stickyEntryIndex = entryIdx;
      } else if (entryIdx >= 0 && entryIdx == _stickyEntryIndex && _stickyQaIndex >= 0) {
        // In a pause within the same entry after at least one Q/A played — hold last state
        qaIdx = _stickyQaIndex;
        isQ = _stickyIsQuestion;
      } else if (entryIdx != _stickyEntryIndex) {
        // Moved to a new entry — reset sticky
        _stickyQaIndex = -1;
        _stickyIsQuestion = false;
        _stickyEntryIndex = entryIdx;
      }

      if (entryIdx != _activeEntryIndex ||
          qaIdx != _activeQaIndex ||
          isQ != _activeIsQuestion) {
        final prevEntryIdx = _activeEntryIndex;
        setState(() {
          _activeEntryIndex = entryIdx;
          _activeQaIndex = qaIdx;
          _activeIsQuestion = isQ;
        });
        // Scroll to entry when sentence block starts
        if (entryIdx >= 0 && entryIdx != prevEntryIdx) {
          _scrollToSentence(entryIdx);
        }
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

  void _prevBlock() {
    final ms = _player.position.inMilliseconds;
    int? target;
    for (final e in _entrySpans.entries) {
      final start = e.value['start']!;
      if (start < ms - 500) {
        if (target == null || start > _entrySpans[target]!['start']!) {
          target = e.key;
        }
      }
    }
    final seekMs = target != null ? _entrySpans[target]!['start']! : 0;
    _player.seek(Duration(milliseconds: seekMs));
    if (target != null) _scrollToSentence(target);
  }

  void _nextBlock() {
    final ms = _player.position.inMilliseconds;
    int? target;
    for (final e in _entrySpans.entries) {
      final start = e.value['start']!;
      if (start > ms) {
        if (target == null || start < _entrySpans[target]!['start']!) {
          target = e.key;
        }
      }
    }
    if (target == null) return;
    _player.seek(Duration(milliseconds: _entrySpans[target]!['start']!));
    _scrollToSentence(target);
  }

  void _toggleLoopBlock() {
    setState(() => _loopBlock = !_loopBlock);
  }

  /// Load the Input Diary content.
  ///
  /// Priority:
  ///   1. input_language_sentence from already-loaded entries (fastest, offline)
  ///   2. Local cache file (offline)
  ///   3. Fetch from server via /api/lessons/entries using the first available variant
  Future<void> _loadDiaryContent() async {
    if (_lessonDate == null) {
      setState(() => _diaryContent = '(No date found in lesson name)');
      return;
    }

    // If we already have entries loaded from any TPRS variant, just show them.
    if (_sentenceEntries.isNotEmpty) {
      final buf = StringBuffer();
      for (var i = 0; i < _sentenceEntries.length; i++) {
        final s = _sentenceEntries[i]['input_language_sentence'] as String? ?? '';
        if (s.isNotEmpty) buf.writeln('${i + 1}. $s');
      }
      if (buf.isNotEmpty) {
        setState(() => _diaryContent = buf.toString().trim());
        return;
      }
    }

    final base = widget.lesson['base'] as String? ?? '';
    final cachePath = await SyncService.localPath('TPRS/$base.diary_input.txt');
    final cacheFile = File(cachePath);

    if (await cacheFile.exists()) {
      setState(() => _diaryContent = cacheFile.readAsStringSync());
      return;
    }

    // Not cached — fetch entries from any available variant to get sentences.
    setState(() {
      _diaryLoading = true;
      _diaryContent = '';
    });
    try {
      final firstVariant = _variants.keys.isNotEmpty
          ? _variantToApiKey(_variants.keys.first)
          : 'original';
      final data = await ApiService.getLessonEntries(_lessonDate!, firstVariant);
      final entries = (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final buf = StringBuffer();
      for (var i = 0; i < entries.length; i++) {
        final s = entries[i]['input_language_sentence'] as String? ?? '';
        if (s.isNotEmpty) buf.writeln('${i + 1}. $s');
      }
      final content = buf.toString().trim();
      if (content.isNotEmpty) {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(content);
      }
      if (mounted) setState(() => _diaryContent = content.isNotEmpty ? content : '(No diary entries found)');
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
    _positionSub?.cancel();
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'Content not available.\nSync the lesson to view it offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredContent() {
    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _sentenceEntries.length,
        itemBuilder: (ctx, i) {
          final entry = _sentenceEntries[i];
          final isEntryActive = i == _activeEntryIndex;
          final isSentenceActive = isEntryActive && _activeQaIndex == -1;
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
            decoration: isEntryActive
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
                              fontWeight: isSentenceActive
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
                ...qa.asMap().entries.map((e) {
                  final j = e.key;
                  final qaPair = e.value;
                  final question = qaPair['question'] as String? ?? '';
                  final answer = qaPair['answer'] as String? ?? '';
                  final questionInput = qaPair['question_input'] as String? ?? '';
                  final answerInput = qaPair['answer_input'] as String? ?? '';
                  final isQActive =
                      isEntryActive && _activeQaIndex == j && _activeIsQuestion;
                  final isAActive =
                      isEntryActive && _activeQaIndex == j && !_activeIsQuestion && _activeQaIndex >= 0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_kwQuestion $question',
                          style: TextStyle(
                            color: isQActive
                                ? const Color(0xFFBF360C)
                                : const Color(0xFFE65100),
                            fontWeight: isQActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: _fontSize,
                          ),
                        ),
                        if (isExpanded && questionInput.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 1),
                            child: Text(
                              questionInput,
                              style: TextStyle(
                                fontSize: _fontSize - 2,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            '$_kwAnswer $answer',
                            style: TextStyle(
                              color: isAActive
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFF2E7D32),
                              fontWeight: isAActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: _fontSize,
                            ),
                          ),
                        ),
                        if (isExpanded && answerInput.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 1),
                            child: Text(
                              answerInput,
                              style: TextStyle(
                                fontSize: _fontSize - 2,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
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

  // ── Scoring bar ───────────────────────────────────────────────────────────────

  Widget _buildScoringBar() {
    final total = _sentenceEntries.length;
    final current = _activeEntryIndex + 1;
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
                  onPressed: () => _scoreEntry(_activeEntryIndex, score),
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

      // Mark synced=true since the server already received it
      await LocalDbService.saveSrsScore(
        date: _lessonDate!,
        entryIndex: idx,
        score: score,
        synced: true,
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
      // Save locally (synced=false) so it can be replayed when back online
      try {
        await LocalDbService.saveSrsScore(
          date: _lessonDate!,
          entryIndex: idx,
          score: score,
          synced: false,
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
                      // Clear entries when switching variants so stale content
                      // from the previous tab is not shown.
                      _sentenceEntries = [];
                      _segments = [];
                      _entrySpans = {};
                      _expandedTranslations.clear();
                      _sentenceKeys.clear();
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
                        tooltip: 'Previous block',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _audioReady && _entrySpans.isNotEmpty
                            ? _prevBlock
                            : null,
                      ),
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
                      IconButton(
                        tooltip: 'Next block',
                        icon: const Icon(Icons.skip_next),
                        onPressed: _audioReady && _entrySpans.isNotEmpty
                            ? _nextBlock
                            : null,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: _loopBlock ? 'Stop block repeat' : 'Repeat current block',
                        icon: Icon(
                          Icons.repeat_one,
                          color: _loopBlock
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: _audioReady ? _toggleLoopBlock : null,
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
          if (_activeEntryIndex >= 0 && _sentenceEntries.isNotEmpty)
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

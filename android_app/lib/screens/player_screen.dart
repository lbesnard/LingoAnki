import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';
import 'drive_mode_screen.dart';

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
  /// audio_timing.start_ms / end_ms stored as floats in older data).
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
  // Auto-cycle through all variants when playback completes
  bool _cycleVariants = false;
  // Guard: prevent _onPlaybackCompleted from firing multiple times per completion
  bool _cycleTriggered = false;
  // Drive Mode
  bool _driveModeAvailable = false;
  int _driveModePauseMs = 600;
  // Canonical variant order — must match the capitalized keys from the API
  // (variant_display = variant.lstrip("_").title() in webapp.py)
  static const _kCanonicalOrder = ['Original', 'Enhanced', 'Present', 'Future'];

  // Sentence timing + highlighting
  List<Map<String, dynamic>> _sentenceEntries = [];
  // Flat list of timed segments: {entryIdx, qaIdx (-1=sentence), isQuestion, timing}
  List<Map<String, dynamic>> _segments = [];
  // Entry-level spans covering the full block (sentence → last answer)
  Map<int, Map<String, int>> _entrySpans = {};
  // First Q/A segment start_ms per entry — used to clear sticky state on backward seek
  Map<int, int> _firstQaStarts = {};
  int _activeEntryIndex = -1;
  int _activeQaIndex = -1; // -1 = sentence is active
  bool _activeIsQuestion = false;
  // Sticky: keep last Q/A highlighted during inter-segment pauses
  int _stickyQaIndex = -1;
  bool _stickyIsQuestion = false;
  int _stickyEntryIndex = -1;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _sentenceKeys = {};
  // Keys for individual Q/A rows: "${entryIdx}_${qaIdx}_q" / "_a"
  final Map<String, GlobalKey> _qaKeys = {};

  // Translation toggle — set of entry indices whose translation is revealed
  final Set<int> _expandedTranslations = {};

  // Scoring state
  int? _scoredSentenceIndex;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _variants = widget.lesson['variants'] as Map<String, dynamic>? ?? {};
    // Sort tabs into canonical order; append Input Diary at the end.
    final orderedVariants =
        _kCanonicalOrder.where((v) => _variants.containsKey(v)).toList();
    final extras =
        _variants.keys.where((v) => !_kCanonicalOrder.contains(v)).toList();
    _tabNames = [...orderedVariants, ...extras, _kInputDiaryTab];
    _currentTab = _tabNames.isNotEmpty ? _tabNames.first : _kInputDiaryTab;

    // Prefer date field from server; fall back to parsing base name.
    final base = widget.lesson['base'] as String? ?? '';
    _lessonDate = widget.lesson['date'] as String? ??
        RegExp(r'TPRS_(\d{4}-\d{2}-\d{2})').firstMatch(base)?.group(1);

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
    final relPath = 'TPRS/$filename';

    // On Android: check local cache exists before loading.
    if (!kIsWeb) {
      final mp3Path = await SyncService.localPath(relPath);
      final audioFile = File(mp3Path);
      if (!await audioFile.exists()) return;
    }

    bool audioSet = false;
    try {
      final uri = await SyncService.audioUri(relPath);
      await _player.setAudioSource(AudioSource.uri(uri));
      audioSet = true;
    } catch (_) {}
    if (audioSet && mounted) {
      setState(() => _audioReady = true);
      _startPositionListener();
    }
  }

  Future<void> _loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final loopDefault = prefs.getBool('lesson_loop_default') ?? false;
    setState(() {
      _kwQuestion = prefs.getString('tprs_question') ?? 'SPØRSMÅL:';
      _kwAnswer = prefs.getString('tprs_answer') ?? 'SVAR:';
      _fontSize = prefs.getDouble('player_font_size') ?? 14.0;
      _loopEnabled = loopDefault;
      _cycleVariants = prefs.getBool('lesson_cycle_variants') ?? false;
    });
    _player.setLoopMode(_loopEnabled ? LoopMode.one : LoopMode.off);
    // Fire-and-forget: config is only needed for Drive Mode; must not block
    // text loading (which hits local SQLite cache and should be instant).
    _fetchAppConfig();
  }

  Future<void> _fetchAppConfig() async {
    try {
      final cfg = await ApiService.fetchAppConfig();
      if (mounted) {
        setState(() {
          _driveModeAvailable = cfg['drive_mode_available'] as bool? ?? false;
          _driveModePauseMs =
              (cfg['pause_between_sentences_duration'] as num?)?.toInt() ?? 600;
        });
      }
    } catch (_) {
      // Drive Mode unavailable if config fetch fails
    }
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

  Future<void> _trackLessonPlay() async {
    if (_lessonDate == null) return;

    final timestamp = DateTime.now().toUtc().toIso8601String();

    // Save locally first (offline support)
    try {
      await LocalDbService.saveLessonLastReviewed(_lessonDate!, timestamp);
    } catch (_) {}

    // Update server in background
    ApiService.updateLessonLastReviewed(_lessonDate!).catchError((_) {
      // Will sync later when online
      return <String, dynamic>{};
    });
  }

  Future<void> _loadVariant(String variantName) async {
    if (variantName.isEmpty || variantName == _kInputDiaryTab) return;

    await _player.stop();
    setState(() {
      _audioReady = false;
      _cycleTriggered = false;
      _activeEntryIndex = -1;
      _activeQaIndex = -1;
      _activeIsQuestion = false;
      _stickyQaIndex = -1;
      _stickyIsQuestion = false;
      _stickyEntryIndex = -1;
    });

    // Load audio (best-effort — file may not be synced yet).
    await _tryLoadAudio(variantName);

    // Fetch structured entries (timings + translations).
    // Strategy: load from day_cache SQLite immediately (instant, offline),
    // then fetch full day data from the API in the background and update cache.
    if (_lessonDate != null) {
      final variantKey = _variantToApiKey(variantName);

      // Local-first: instant display from day_cache SQLite.
      await _loadEntriesFromDayCache(variantKey);

      // Background API refresh — fetches full day data and updates day_cache.
      ApiService.getDayData(_lessonDate!).then((dayData) {
        if (mounted) {
          LocalDbService.saveDayCache(_lessonDate!, dayData).catchError((_) {});
          _applyEntriesFromDayData(dayData, variantKey);
        }
      }).catchError((_) {
        // Server unreachable — local cache already shown, nothing to do.
        debugPrint(
            '[PlayerScreen] Offline mode active: relying completely on local SQLite cache.');
      });
    }
  }

  /// Load entries for [variantKey] from the local day_cache SQLite table.
  /// On web there is no local cache — this is skipped and the server
  /// data (already loaded via the API) is used instead.
  Future<void> _loadEntriesFromDayCache(String variantKey) async {
    if (_lessonDate == null || kIsWeb) return;
    try {
      final dayData = await LocalDbService.getDayCache(_lessonDate!);
      if (dayData == null) return;
      _applyEntriesFromDayData(dayData, variantKey);
    } catch (e, st) {
      debugPrint('_loadEntriesFromDayCache error: $e\n$st');
    }
  }

  /// Extract and apply entries for [variantKey] from a full Day object.
  void _applyEntriesFromDayData(
      Map<String, dynamic> dayData, String variantKey) {
    final rawEntries = (dayData['entries'] as List?) ?? [];
    final entries = rawEntries
        .map((e) {
          final em = e as Map<String, dynamic>;
          final lessonsMap = em['lessons'] as Map<String, dynamic>? ?? {};

          // Locate the key case-insensitively so that both
          // capitalized and lowercased API schemas match smoothly.
          final matchingKey = lessonsMap.keys.firstWhere(
            (k) => k.toLowerCase() == variantKey.toLowerCase(),
            orElse: () => variantKey,
          );
          final lesson = lessonsMap[matchingKey] as Map<String, dynamic>? ?? {};

          return <String, dynamic>{
            'index': em['index'],
            'sentence': lesson['sentence'] ?? '',
            'sentence_input': lesson['sentence_input'] ?? '',
            'sentence_audio_path': lesson['sentence_audio_path'] ?? '',
            'sentence_input_language_audio_path':
                lesson['sentence_input_language_audio_path'] ?? '',
            'input_language_sentence': em['input_language_sentence'] ?? '',
            'output_language_translation':
                em['output_language_translation'] ?? '',
            'audio_timing': lesson['audio_timing'],
            'qa': lesson['qa'] ?? [],
            'reviewing': (em['lessons'] as Map<String, dynamic>?)?['reviewing'],
          };
        })
        .cast<Map<String, dynamic>>()
        .toList();

    if (mounted && entries.isNotEmpty) {
      _applyEntries(entries);
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
      _qaKeys.clear();
      for (var i = 0; i < entries.length; i++) {
        _sentenceKeys[i] = GlobalKey();
        final qa = entries[i]['qa'] as List<dynamic>? ?? [];
        for (var j = 0; j < qa.length; j++) {
          _qaKeys['${i}_${j}_q'] = GlobalKey();
          _qaKeys['${i}_${j}_a'] = GlobalKey();
        }
      }
    });
    _buildSegmentList();
  }

  String _variantToApiKey(String variantName) {
    return variantName.toLowerCase();
  }

  Future<void> _enterDriveMode() async {
    if (_sentenceEntries.isEmpty) return;
    final l10n = AppLocalizations.of(context);

    // Check if Input Language audio paths are present in loaded entries
    final hasInputAudio = _sentenceEntries.any((e) =>
        (e['sentence_input_language_audio_path'] as String?)?.isNotEmpty ==
        true);

    if (!hasInputAudio) {
      // Check if drive mode is even configured on server
      if (!_driveModeAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.driveModeConfigMissing)),
          );
        }
        return;
      }

      // Offer to trigger generation
      bool confirmed = false;
      if (mounted) {
        confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.driveModeGenerateTitle),
                content: Text(l10n.driveModeGenerateBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child:
                        Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.driveModeGenerateConfirm),
                  ),
                ],
              ),
            ) ??
            false;
      }

      if (!confirmed || !mounted) return;

      // Trigger generation
      try {
        await ApiService.triggerDriveModeAudioBackfill(date: _lessonDate);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.driveModeOfflineError)),
          );
        }
        return;
      }

      // Poll for completion via /api/generate/status — show progress dialog
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _DriveModeGeneratingDialog(
            onDone: () => Navigator.pop(ctx),
          ),
        );
      }

      // Re-sync this day's entries to get the new audio paths.
      if (_lessonDate != null) {
        try {
          final variantKey = _variantToApiKey(_currentTab);
          final data = await ApiService.getDayData(_lessonDate!);
          if (mounted) {
            _applyEntriesFromDayData(data, variantKey);
            await LocalDbService.saveDayCache(_lessonDate!, data)
                .catchError((_) {});
          }
        } catch (_) {}
      }
    }

    if (!mounted || _sentenceEntries.isEmpty) return;

    // Pause current playback before entering Drive Mode to avoid overlapping audio
    if (_player.playing) {
      await _player.pause();
    }

    // Navigate to Drive Mode screen
    final variantKey = _variantToApiKey(_currentTab);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriveModeScreen(
          entries: List.unmodifiable(_sentenceEntries),
          variantKey: variantKey,
          lessonTitle: widget.lesson['display'] as String? ?? '',
          pauseMs: _driveModePauseMs,
          lessonDate: _lessonDate,
        ),
      ),
    );
  }

  void _buildSegmentList() {
    final segs = <Map<String, dynamic>>[];
    final spans = <int, Map<String, int>>{}; // entryIdx → {start, end}
    final firstQaStarts =
        <int, int>{}; // entryIdx → start_ms of first Q/A segment

    for (var i = 0; i < _sentenceEntries.length; i++) {
      final entry = _sentenceEntries[i];
      final st = entry['audio_timing'] as Map<String, dynamic>?;
      int blockStart = _toInt(st?['start_ms']);
      int blockEnd = _toInt(st?['end_ms']);

      if (st != null && blockEnd > 0) {
        segs.add(
            {'entryIdx': i, 'qaIdx': -1, 'isQuestion': false, 'timing': st});
      }
      final qa = (entry['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (var j = 0; j < qa.length; j++) {
        final qt = qa[j]['question_timing'] as Map<String, dynamic>?;
        if (qt != null && _toInt(qt['end_ms']) > 0) {
          segs.add(
              {'entryIdx': i, 'qaIdx': j, 'isQuestion': true, 'timing': qt});
          final start = _toInt(qt['start_ms']);
          final end = _toInt(qt['end_ms']);
          if (end > blockEnd) blockEnd = end;
          if (!firstQaStarts.containsKey(i) || start < firstQaStarts[i]!) {
            firstQaStarts[i] = start;
          }
        }
        final at = qa[j]['answer_timing'] as Map<String, dynamic>?;
        if (at != null && _toInt(at['end_ms']) > 0) {
          segs.add(
              {'entryIdx': i, 'qaIdx': j, 'isQuestion': false, 'timing': at});
          final end = _toInt(at['end_ms']);
          if (end > blockEnd) blockEnd = end;
        }
      }
      if (blockEnd > 0) spans[i] = {'start': blockStart, 'end': blockEnd};
    }
    _segments = segs;
    _entrySpans = spans;
    _firstQaStarts = firstQaStarts;
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
          // Immediately update cursor and scroll to first sentence in block
          setState(() {
            _activeEntryIndex = _activeEntryIndex;
            _activeQaIndex = -1;
            _activeIsQuestion = false;
            // Reset sticky state to ensure clean transition
            _stickyQaIndex = -1;
            _stickyIsQuestion = false;
            _stickyEntryIndex = _activeEntryIndex;
          });
          _scrollToSentence(_activeEntryIndex);
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
      } else if (entryIdx >= 0 &&
          entryIdx == _stickyEntryIndex &&
          _stickyQaIndex >= 0) {
        // In a pause within the same entry — hold last Q/A bold, BUT only if we
        // are past the first Q/A start.
        final firstQaStart = _firstQaStarts[entryIdx];
        if (firstQaStart != null && ms >= firstQaStart) {
          qaIdx = _stickyQaIndex;
          isQ = _stickyIsQuestion;
        } else {
          _stickyQaIndex = -1;
          _stickyIsQuestion = false;
        }
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
        final prevQaIdx = _activeQaIndex;
        final prevIsQ = _activeIsQuestion;
        setState(() {
          _activeEntryIndex = entryIdx;
          _activeQaIndex = qaIdx;
          _activeIsQuestion = isQ;
        });
        // New sentence block → center on the sentence container
        if (entryIdx >= 0 && entryIdx != prevEntryIdx) {
          _scrollToSentence(entryIdx);
        } else if (entryIdx >= 0 &&
            qaIdx >= 0 &&
            (qaIdx != prevQaIdx || isQ != prevIsQ)) {
          // Q/A changed within same block → center on the active Q or A row
          _scrollToQA(entryIdx, qaIdx, isQ);
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
      alignment: 0.08,
    );
  }

  void _scrollToQA(int entryIdx, int qaIdx, bool isQuestion) {
    final mapKey = '${entryIdx}_${qaIdx}_${isQuestion ? 'q' : 'a'}';
    final key = _qaKeys[mapKey];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5,
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
    if (_loopBlock && _activeEntryIndex >= 0) {
      setState(() {
        _activeQaIndex = -1;
        _activeIsQuestion = false;
        _stickyQaIndex = -1;
        _stickyIsQuestion = false;
      });
      _scrollToSentence(_activeEntryIndex);
    }
  }

  void _toggleCycleVariants() async {
    setState(() => _cycleVariants = !_cycleVariants);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lesson_cycle_variants', _cycleVariants);
  }

  Future<void> _onPlaybackCompleted() async {
    if (!_cycleVariants || _cycleTriggered) return;
    setState(() => _cycleTriggered = true);
    final available =
        _kCanonicalOrder.where((v) => _variants.containsKey(v)).toList();
    if (available.isEmpty) return;
    final currentIdx = available.indexOf(_currentTab);
    if (currentIdx < 0 || currentIdx >= available.length - 1) {
      return;
    }
    final nextTab = available[currentIdx + 1];
    setState(() => _currentTab = nextTab);
    await _loadVariant(nextTab);
    for (var i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_audioReady) break;
    }
    if (mounted && _audioReady) {
      await _player.seek(Duration.zero);
      await _player.play();
    }
  }

  Future<void> _loadDiaryContent() async {
    if (_lessonDate == null) {
      setState(() => _diaryContent = '(No date found in lesson name)');
      return;
    }

    if (_sentenceEntries.isNotEmpty) {
      final buf = StringBuffer();
      for (var i = 0; i < _sentenceEntries.length; i++) {
        final s =
            _sentenceEntries[i]['input_language_sentence'] as String? ?? '';
        if (s.isNotEmpty) buf.writeln('${i + 1}. $s');
      }
      if (buf.isNotEmpty) {
        setState(() => _diaryContent = buf.toString().trim());
        return;
      }
    }

    final base = widget.lesson['base'] as String? ?? '';

    if (!kIsWeb) {
      final cachePath =
          await SyncService.localPath('TPRS/$base.diary_input.txt');
      final cacheFile = File(cachePath);
      if (await cacheFile.exists()) {
        setState(() => _diaryContent = cacheFile.readAsStringSync());
        return;
      }
    }

    setState(() {
      _diaryLoading = true;
      _diaryContent = '';
    });
    try {
      final firstVariant = _variants.keys.isNotEmpty
          ? _variantToApiKey(_variants.keys.first)
          : 'original';
      final data =
          await ApiService.getLessonEntries(_lessonDate!, firstVariant);
      final entries =
          (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final buf = StringBuffer();
      for (var i = 0; i < entries.length; i++) {
        final s = entries[i]['input_language_sentence'] as String? ?? '';
        if (s.isNotEmpty) buf.writeln('${i + 1}. $s');
      }
      final content = buf.toString().trim();
      if (content.isNotEmpty && !kIsWeb) {
        final cachePath =
            await SyncService.localPath('TPRS/$base.diary_input.txt');
        final cacheFile = File(cachePath);
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(content);
      }
      if (mounted) {
        setState(() => _diaryContent =
            content.isNotEmpty ? content : '(No diary entries found)');
      }
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
    SyncManager.instance.syncLesson(base, date: _lessonDate);
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
          final sentenceInput = entry['sentence_input'] as String? ?? '';
          final inputSentence =
              entry['input_language_sentence'] as String? ?? '';
          final displayInput = (_currentTab.toLowerCase() != 'original' &&
                  sentenceInput.isNotEmpty)
              ? sentenceInput
              : inputSentence;
          final outputTranslation =
              entry['output_language_translation'] as String? ?? '';
          final qa = (entry['qa'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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
                          isExpanded ? Icons.visibility : Icons.visibility_off,
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
                if (isExpanded &&
                    (displayInput.isNotEmpty || outputTranslation.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (displayInput.isNotEmpty)
                          Text(
                            displayInput,
                            style: TextStyle(
                              fontSize: _fontSize - 1,
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (_currentTab.toLowerCase() == 'original' &&
                            outputTranslation.isNotEmpty &&
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
                ...qa.asMap().entries.map((e) {
                  final j = e.key;
                  final qaPair = e.value;
                  final question = qaPair['question'] as String? ?? '';
                  final answer = qaPair['answer'] as String? ?? '';
                  final questionInput =
                      qaPair['question_input'] as String? ?? '';
                  final answerInput = qaPair['answer_input'] as String? ?? '';
                  final isQActive =
                      isEntryActive && _activeQaIndex == j && _activeIsQuestion;
                  final isAActive = isEntryActive &&
                      _activeQaIndex == j &&
                      !_activeIsQuestion &&
                      _activeQaIndex >= 0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyedSubtree(
                          key: _qaKeys['${i}_${j}_q'],
                          child: Text(
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
                        KeyedSubtree(
                          key: _qaKeys['${i}_${j}_a'],
                          child: Padding(
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

    int localId = 0;
    try {
      localId = await LocalDbService.saveSrsScore(
        date: _lessonDate!,
        entryIndex: idx,
        score: score,
        synced: true,
      );
    } catch (_) {}

    final savedId = localId;
    ApiService.scoreEntry(_lessonDate!, idx, score).then((result) {
      if (mounted) {
        final reviewing = result['reviewing'] as Map<String, dynamic>?;
        final intervalDays = reviewing?['interval_days'] as int?;
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
    }).catchError((e) {
      if (savedId > 0) LocalDbService.resetScoreSynced(savedId);
      if (mounted) {
        final isOffline = e is SocketException || e is TimeoutException;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline
                ? 'Score saved (will sync when online)'
                : 'Score saved locally — sync error: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _diaryContent,
        style:
            TextStyle(fontSize: _fontSize, color: Colors.black87, height: 1.6),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = widget.lesson['display'] as String? ?? '';
    final isInputDiary = _currentTab == _kInputDiaryTab;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l10n.fontSizeTooltip(_fontSize.toStringAsFixed(0)),
            icon: const Icon(Icons.text_fields),
            onPressed: _cycleFontSize,
          ),
          IconButton(
            tooltip: l10n.driveModeTooltip,
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: _enterDriveMode,
          ),
          IconButton(
            tooltip: _loopEnabled ? l10n.loopOn : l10n.loopOff,
            icon: Icon(
              _loopEnabled ? Icons.repeat_one : Icons.repeat,
              color: _loopEnabled ? Colors.blue.shade400 : null,
            ),
            onPressed: _toggleLoop,
          ),
          IconButton(
            tooltip:
                _cycleVariants ? 'Cycle variants: on' : 'Cycle variants: off',
            icon: Icon(
              Icons.playlist_play,
              color: _cycleVariants ? Colors.blue.shade400 : null,
            ),
            onPressed: _toggleCycleVariants,
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
                  onSelectionChanged: (sel) {
                    final tab = sel.first;
                    setState(() {
                      _currentTab = tab;
                      _audioReady = false;
                      // REMOVED: _sentenceEntries = [];
                      // REMOVED: _segments = [];
                      // REMOVED: _entrySpans = {};
                      // REMOVED: _expandedTranslations.clear();
                      // REMOVED: _sentenceKeys.clear();
                    });

                    if (tab == _kInputDiaryTab) {
                      _player.stop();
                      _loadDiaryContent();
                    } else {
                      _loadVariant(tab);
                    }
                  },
                  selected: {_currentTab},
                ),
              ),
            ),
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
                        tooltip: l10n.previousBlock,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _audioReady && _entrySpans.isNotEmpty
                            ? _prevBlock
                            : null,
                      ),
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
                          final state = snap.data;
                          final playing = state?.playing ?? false;
                          final completed = state?.processingState ==
                              ProcessingState.completed;
                          if (completed && _cycleVariants && _audioReady) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _onPlaybackCompleted();
                            });
                          }
                          return IconButton(
                            iconSize: 48,
                            icon: Icon(
                              !_audioReady
                                  ? Icons.play_circle_outline
                                  : completed && !_cycleVariants
                                      ? Icons.replay_circle_filled
                                      : playing
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                              color: !_audioReady ? Colors.grey : null,
                            ),
                            onPressed: !_audioReady
                                ? () {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text(
                                          '⏳ Audio not downloaded yet — syncing now, please wait…'),
                                      duration: Duration(seconds: 4),
                                    ));
                                    _triggerSync();
                                  }
                                : () async {
                                    if (!playing && !completed) {
                                      _trackLessonPlay();
                                    }

                                    if (completed) {
                                      await _player.seek(Duration.zero);
                                      await _player.play();
                                    } else if (playing) {
                                      await _player.pause();
                                    } else {
                                      await _player.play();
                                    }
                                  },
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
                      IconButton(
                        tooltip: l10n.nextBlock,
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
                        tooltip: _loopBlock
                            ? 'Stop block repeat'
                            : 'Repeat current block',
                        icon: Icon(
                          _loopBlock ? Icons.repeat_one : Icons.repeat,
                          color: _loopBlock ? Colors.blue.shade400 : null,
                        ),
                        onPressed: _audioReady ? _toggleLoopBlock : null,
                      ),
                    ],
                  ),
                  if (!_audioReady)
                    ListenableBuilder(
                      listenable: SyncManager.instance,
                      builder: (_, __) {
                        final syncing = SyncManager.instance.isSyncing;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                Colors.orange.shade900.withValues(alpha: 0.15),
                            border: Border.all(
                                color: Colors.orange.shade700, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              syncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.orange))
                                  : const Icon(Icons.sync_problem,
                                      color: Colors.orange, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  syncing
                                      ? 'Downloading audio… please wait'
                                      : 'Audio not downloaded — tap ▶ or sync ⟳ to download',
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          if (_activeEntryIndex >= 0 && _sentenceEntries.isNotEmpty)
            _buildScoringBar(),
          Expanded(
            child: isInputDiary ? _buildDiaryContent() : _buildTprsContent(),
          ),
        ],
      ),
    );
  }
}

class _DriveModeGeneratingDialog extends StatefulWidget {
  final VoidCallback onDone;
  const _DriveModeGeneratingDialog({required this.onDone});

  @override
  State<_DriveModeGeneratingDialog> createState() =>
      _DriveModeGeneratingDialogState();
}

class _DriveModeGeneratingDialogState
    extends State<_DriveModeGeneratingDialog> {
  String _status = '';
  bool _done = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    while (!_done && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) break;
      try {
        final result = await ApiService.pollGenerateStatus(_offset);
        final log = result['log'] as String? ?? '';
        final done = result['done'] as bool? ?? false;
        final newOffset = result['offset'] as int? ?? _offset;
        if (mounted) {
          setState(() {
            _offset = newOffset;
            if (log.isNotEmpty) {
              final lines =
                  log.split('\n').where((l) => l.trim().isNotEmpty).toList();
              if (lines.isNotEmpty) _status = lines.last;
            }
            _done = done;
          });
        }
        if (done) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) widget.onDone();
          break;
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generating Drive Mode audio\u2026'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status,
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

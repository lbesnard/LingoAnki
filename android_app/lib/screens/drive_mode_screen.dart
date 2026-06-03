import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';

import '../l10n/app_localizations.dart';
import '../services/sync_service.dart';

import '../utils/web_audio.dart' as web;

/// Drive Mode screen: audio-first hands-free lesson playback.
///
/// Plays a sequential playlist of individual audio segment files per
/// **Sentence Block** (flattened for granular scroll alignment). Bold-highlights
/// the currently playing item. Highlighting is driven by playlist index.
class DriveModeScreen extends StatefulWidget {
  /// Lesson entries from PlayerScreen._sentenceEntries (already loaded).
  final List<Map<String, dynamic>> entries;

  /// Variant key e.g. 'original', 'enhanced', 'present', 'future'.
  final String variantKey;

  final String lessonTitle;

  /// Pause between segments in milliseconds (from server config).
  final int pauseMs;
  final String? lessonDate;

  const DriveModeScreen({
    super.key,
    required this.entries,
    required this.variantKey,
    required this.lessonTitle,
    required this.pauseMs,
    this.lessonDate,
  });

  @override
  State<DriveModeScreen> createState() => _DriveModeScreenState();
}

/// One playable item inside the flattened playlist layout structure.
class _PlaylistItem {
  final int entryIndex;
  final int qaIndex; // -1 = sentence
  final bool isInput; // true = Input Language audio
  final bool isQuestion; // only meaningful when qaIndex >= 0
  final String audioPath; // relative path served by server
  final String text; // text to display on this row

  const _PlaylistItem({
    required this.entryIndex,
    required this.qaIndex,
    required this.isInput,
    required this.isQuestion,
    required this.audioPath,
    required this.text,
  });
}

class _DriveModeScreenState extends State<DriveModeScreen> {
  // ── Playback engines ──
  /// APK only: just_audio player. Null on web.
  AudioPlayer? _player;

  /// Web only: bare HTMLAudioElement. Null on APK.
  web.HTMLAudioElement? _webAudio;

  // ── UI state ──
  static const List<double> _fontSizes = [12.0, 14.0, 20.0, 26.0];
  double _fontSize = 26.0;

  late List<_PlaylistItem> _flatPlaylist;
  int _playlistIndex = 0;
  int _blockStartIndex =
      0; // Start of current block for proper block-level repeating
  bool _repeatBlock = false;
  bool _loopLesson = false; // Repeat entire lesson from start when finished
  bool _playing = false;

  // ── Auto-scroll mechanics ──
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // ── Loop control ──
  int _generation = 0;

  /// Completer for the item currently being awaited inside `_playOne`.
  Completer<_ItemResult>? _currentItem;

  /// Active web listeners typed dynamically to satisfy both implementations
  dynamic _webEndedListener;
  dynamic _webErrorListener;

  @override
  void initState() {
    super.initState();
    _flatPlaylist = _buildFlatPlaylist();

    // Call an async initialization method
    _initializeScreenPlayback();
  }

  Future<void> _initializeScreenPlayback() async {
    if (kIsWeb) {
      _webAudio = web.HTMLAudioElement();
      _webAudio!.preload = 'auto';
    } else {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());

      _player = AudioPlayer();
    }

    if (_flatPlaylist.isNotEmpty && mounted) {
      _runDriveMode();
    }

    final androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "LingoDiary Drive Mode",
      notificationText: "Playing your lesson in the background",
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon:
          AndroidResource(name: 'background_icon', defType: 'drawable'),
    );

    bool hasPermissions =
        await FlutterBackground.initialize(androidConfig: androidConfig);

    if (hasPermissions) {
      await FlutterBackground.enableBackgroundExecution();
    }
  }

  @override
  void dispose() {
    _generation++;
    _currentItem?.complete(_ItemResult.cancelled);
    _detachWebListeners();
    _webAudio?.pause();
    _webAudio?.removeAttribute('src');
    _player?.dispose();

    if (!kIsWeb) {
      FlutterBackground.disableBackgroundExecution();
    }

    super.dispose();
  }

  // ── Auto-scroll Helper ──────────────────────────────────────────────────────

  void _scrollToBlock(int index) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.3,
          );
        }
      } catch (e) {
        debugPrint('[DriveMode] Scroll tracking error: $e');
      }
    });
  }

  // ── Build playlist ──────────────────────────────────────────────────────────

  List<_PlaylistItem> _buildFlatPlaylist() {
    final playlist = <_PlaylistItem>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final entry = widget.entries[i];

      final sentencePath = (entry['sentence_audio_path'] as String?) ?? '';
      final sentenceInputPath =
          (entry['sentence_input_language_audio_path'] as String?) ?? '';
      final sentenceText = (entry['sentence'] as String?) ?? '';
      final sentenceInputText = (entry['sentence_input'] as String?) ?? '';

      if (sentenceInputPath.isNotEmpty) {
        playlist.add(_PlaylistItem(
          entryIndex: i,
          qaIndex: -1,
          isInput: true,
          isQuestion: false,
          audioPath: sentenceInputPath,
          text: sentenceInputText,
        ));
      }
      if (sentencePath.isNotEmpty) {
        playlist.add(_PlaylistItem(
          entryIndex: i,
          qaIndex: -1,
          isInput: false,
          isQuestion: false,
          audioPath: sentencePath,
          text: sentenceText,
        ));
      }

      final qaList = (entry['qa'] as List<dynamic>?) ?? [];
      for (var j = 0; j < qaList.length; j++) {
        final qa = qaList[j] as Map<String, dynamic>;
        final qPath = (qa['question_audio_path'] as String?) ?? '';
        final qInputPath =
            (qa['question_input_language_audio_path'] as String?) ?? '';
        final aPath = (qa['answer_audio_path'] as String?) ?? '';
        final aInputPath =
            (qa['answer_input_language_audio_path'] as String?) ?? '';
        final qText = (qa['question'] as String?) ?? '';
        final qInputText = (qa['question_input'] as String?) ?? '';
        final aText = (qa['answer'] as String?) ?? '';
        final aInputText = (qa['answer_input'] as String?) ?? '';

        if (qInputPath.isNotEmpty) {
          playlist.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: true,
            isQuestion: true,
            audioPath: qInputPath,
            text: qInputText,
          ));
        }
        if (qPath.isNotEmpty) {
          playlist.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: false,
            isQuestion: true,
            audioPath: qPath,
            text: qText,
          ));
        }
        if (aInputPath.isNotEmpty) {
          playlist.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: true,
            isQuestion: false,
            audioPath: aInputPath,
            text: aInputText,
          ));
        }
        if (aPath.isNotEmpty) {
          playlist.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: false,
            isQuestion: false,
            audioPath: aPath,
            text: aText,
          ));
        }
      }
    }
    return playlist;
  }

  Future<void> _trackLessonPlay() async {
    if (widget.lessonDate == null) return;

    final timestamp = DateTime.now().toUtc().toIso8601String();

    // Save locally first (offline support)
    try {
      await LocalDbService.saveLessonLastReviewed(
          widget.lessonDate!, timestamp);
    } catch (_) {}

    // Update server in background
    ApiService.updateLessonLastReviewed(widget.lessonDate!).catchError((_) {
      // Background sync engine picks this up later when online
      return <String, dynamic>{};
    });
  }

  // ── Main loop ───────────────────────────────────────────────────────────────

  Future<void> _runDriveMode() async {
    final gen = ++_generation;
    if (mounted) setState(() => _playing = true);

    if (_flatPlaylist.isNotEmpty) {
      _scrollToBlock(_playlistIndex);
    }

    // Trigger tracking immediately when Drive Mode playback starts
    _trackLessonPlay();

    while (mounted &&
        gen == _generation &&
        _playlistIndex < _flatPlaylist.length) {
      final item = _flatPlaylist[_playlistIndex];
      int playCount = 0;

      while (mounted && gen == _generation) {
        // Wait if paused
        while (!_playing && gen == _generation && mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (!mounted || gen != _generation) return;

        debugPrint(
            '[DriveMode] play flat track[$_playlistIndex] ${item.audioPath}');

        final result = await _playOne(item);
        if (!mounted || gen != _generation) return;

        if (result == _ItemResult.error) {
          if (mounted) setState(() => _playing = false);
          return;
        }

        playCount++;

        // Only repeat if it's NOT an input language file and it hasn't played twice yet.
        if (!item.isInput && playCount < 2) {
          await Future.delayed(Duration(milliseconds: widget.pauseMs));
          if (!mounted || gen != _generation) return;
          continue;
        }

        break;
      }

      if (!mounted || gen != _generation) return;

      // Check if we're at the end of the current block
      if (_playlistIndex + 1 < _flatPlaylist.length) {
        final nextItem = _flatPlaylist[_playlistIndex + 1];
        final isNewBlock = nextItem.entryIndex != item.entryIndex;

        // If we're about to move to a new block and repeat is enabled, jump back to block start
        if (isNewBlock && _repeatBlock) {
          await Future.delayed(Duration(milliseconds: widget.pauseMs));
          if (mounted) {
            setState(() => _playlistIndex = _blockStartIndex);
          }
        } else {
          // Normal advancement to next item
          final dynamicDelay = isNewBlock ? widget.pauseMs * 2 : widget.pauseMs;

          await Future.delayed(Duration(milliseconds: dynamicDelay));
          if (!mounted || gen != _generation) return;

          setState(() {
            _playlistIndex++;
            // Track block start when entering a new block
            if (isNewBlock) {
              _blockStartIndex = _playlistIndex;
            }
          });
          _scrollToBlock(_playlistIndex);
        }
      } else {
        // Reached end of lesson
        if (mounted) {
          setState(() => _playing = false);
          // If lesson loop is enabled, restart from beginning
          if (_loopLesson) {
            setState(() {
              _playlistIndex = 0;
              _blockStartIndex = 0;
              _playing = true;
            });
            await Future.delayed(Duration(milliseconds: widget.pauseMs * 2));
            if (!mounted || gen != _generation) return;
            _runDriveMode();
            return;
          }
        }
        return;
      }
    }
  }

  /// Plays one item to completion.
  Future<_ItemResult> _playOne(_PlaylistItem item) async {
    final completer = Completer<_ItemResult>();
    _currentItem = completer;

    String? src;
    try {
      final targetPath = item.audioPath.startsWith('TPRS/')
          ? item.audioPath
          : 'TPRS/${item.audioPath}';

      final uri = await SyncService.ensureLocalAndGetUri(targetPath);

      if (uri == null) {
        debugPrint(
            '[DriveMode] ERROR: audio path resolved to null ($targetPath)');
        if (!completer.isCompleted) completer.complete(_ItemResult.error);
        return completer.future;
      }
      src = uri.toString();
    } catch (e) {
      debugPrint(
          '[DriveMode] ERROR: ensureLocalAndGetUri threw for ${item.audioPath}: $e');
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
      return completer.future;
    }

    if (kIsWeb) {
      _playOneWeb(src, completer);
    } else {
      await _playOneNative(src, completer);
    }

    final result = await completer.future;
    if (identical(_currentItem, completer)) _currentItem = null;
    return result;
  }

  // ── APK / native playback ───────────────────────────────────────────────────

  Future<void> _playOneNative(
      String src, Completer<_ItemResult> completer) async {
    final player = _player!;
    StreamSubscription<ProcessingState>? sub;

    try {
      Uri audioUri;
      if (src.startsWith('http://') || src.startsWith('https://')) {
        audioUri = Uri.parse(src);
      } else if (src.startsWith('file://')) {
        audioUri = Uri.parse(src);
      } else {
        audioUri = Uri.file(src);
      }

      debugPrint('[DriveMode] Native Player loading URI: $audioUri');

      await player.setAudioSource(AudioSource.uri(audioUri));

      if (completer.isCompleted) return;

      sub = player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          sub?.cancel();
          if (!completer.isCompleted) completer.complete(_ItemResult.ok);
        }
      }, onError: (Object e) {
        debugPrint('[DriveMode] ERROR: native processingState error: $e');
        sub?.cancel();
        if (!completer.isCompleted) completer.complete(_ItemResult.error);
      });

      await player.play();
    } catch (e) {
      debugPrint('[DriveMode] ERROR: native playback threw for $src: $e');
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
    }

    completer.future.whenComplete(() => sub?.cancel());
  }

  // ── Web playback ────────────────────────────────────────────────────────────

  void _playOneWeb(String src, Completer<_ItemResult> completer) {
    final audio = _webAudio!;
    _detachWebListeners();

    void onEnded(web.Event _) {
      _detachWebListeners();
      if (!completer.isCompleted) completer.complete(_ItemResult.ok);
    }

    void onError(web.Event _) {
      final err = audio.error;
      debugPrint('[DriveMode] ERROR: HTMLAudioElement error '
          'code=${err?.code} msg="${err?.message}" src=$src');
      _detachWebListeners();
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
    }

    final endedCb = web.convertEndedCallback(onEnded);
    final errorCb = web.convertErrorCallback(onError);

    _webEndedListener = endedCb;
    _webErrorListener = errorCb;
    audio.addEventListener('ended', endedCb);
    audio.addEventListener('error', errorCb);

    audio.src = src;
    audio.play();
  }

  void _detachWebListeners() {
    final audio = _webAudio;
    if (audio == null) return;
    final ended = _webEndedListener;
    if (ended != null) audio.removeEventListener('ended', ended);
    final error = _webErrorListener;
    if (error != null) audio.removeEventListener('error', error);
    _webEndedListener = null;
    _webErrorListener = null;
  }

  // ── Controls ────────────────────────────────────────────────────────────────

  Future<void> _pauseAudio() async {
    if (kIsWeb) {
      _webAudio?.pause();
    } else {
      await _player?.pause();
    }
  }

  Future<void> _resumeAudio() async {
    if (kIsWeb) {
      _webAudio?.play();
    } else {
      await _player?.play();
    }
  }

  Future<void> _stopAudio() async {
    if (kIsWeb) {
      _webAudio?.pause();
    } else {
      await _player?.stop();
    }
  }

  Future<void> _interruptForNavigation() async {
    _generation++;
    _currentItem?.complete(_ItemResult.cancelled);
    _currentItem = null;
    _detachWebListeners();
    await _stopAudio();
  }

  Future<void> _prevBlock() async {
    await _interruptForNavigation();
    if (_flatPlaylist.isEmpty) return;
    if (_playlistIndex == 0) {
      _runDriveMode();
      return;
    }

    final currentEntryIdx = _flatPlaylist[_playlistIndex].entryIndex;
    int targetIdx = _playlistIndex;

    // 1. Move out of the current block to the previous track context segment
    while (targetIdx > 0 &&
        _flatPlaylist[targetIdx].entryIndex == currentEntryIdx) {
      targetIdx--;
    }

    // 2. Snap backwards to the first track layout element of that upstream block
    final targetEntryIdx = _flatPlaylist[targetIdx].entryIndex;
    while (targetIdx > 0 &&
        _flatPlaylist[targetIdx - 1].entryIndex == targetEntryIdx) {
      targetIdx--;
    }

    setState(() {
      _playlistIndex = targetIdx;
      _blockStartIndex =
          targetIdx; // Update block start for repeat functionality
    });
    _scrollToBlock(_playlistIndex);
    _runDriveMode();
  }

  Future<void> _goNextBlock() async {
    await _interruptForNavigation();
    if (_flatPlaylist.isEmpty) return;

    final currentEntryIdx = _flatPlaylist[_playlistIndex].entryIndex;
    int targetIdx = _playlistIndex;

    // Scan forward entirely past the current entry block boundary
    while (targetIdx < _flatPlaylist.length &&
        _flatPlaylist[targetIdx].entryIndex == currentEntryIdx) {
      targetIdx++;
    }

    if (targetIdx >= _flatPlaylist.length) {
      setState(() => _playing = false);
      return;
    }

    setState(() {
      _playlistIndex = targetIdx;
      _blockStartIndex =
          targetIdx; // Update block start for repeat functionality
    });
    _scrollToBlock(_playlistIndex);
    _runDriveMode();
  }

  Future<void> _restartLesson() async {
    await _interruptForNavigation();
    setState(() {
      _playlistIndex = 0;
      _blockStartIndex = 0;
    });
    _scrollToBlock(_playlistIndex);
    _runDriveMode();
  }

  void _toggleRepeatBlock() {
    setState(() => _repeatBlock = !_repeatBlock);
  }

  void _toggleLoopLesson() {
    setState(() => _loopLesson = !_loopLesson);
  }

  void _cycleFontSize() {
    final idx = _fontSizes.indexOf(_fontSize);
    final next = _fontSizes[(idx + 1) % _fontSizes.length];
    setState(() => _fontSize = next);
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Estimate current visual block numbers safely from the flat index tracker
    final totalBlocks = widget.entries.length;
    final blockNum =
        _flatPlaylist.isNotEmpty && _playlistIndex < _flatPlaylist.length
            ? _flatPlaylist[_playlistIndex].entryIndex + 1
            : (totalBlocks > 0 ? 1 : 0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.lessonTitle,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: l10n.fontSizeTooltip(_fontSize.toStringAsFixed(0)),
            icon: const Icon(Icons.text_fields, color: Colors.white),
            onPressed: _cycleFontSize,
          ),
          IconButton(
            tooltip: _loopLesson ? 'Loop lesson ON' : 'Loop lesson OFF',
            icon: Icon(
              Icons.repeat,
              color: _loopLesson ? Colors.blue.shade300 : Colors.white,
            ),
            onPressed: _toggleLoopLesson,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.grey.shade900,
            child: Text(
              totalBlocks > 0
                  ? l10n.driveModeBlockOf(blockNum, totalBlocks)
                  : '—',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _flatPlaylist.isEmpty
                ? Center(
                    child: Text(
                      l10n.driveModeAudioPending,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: const EdgeInsets.all(20),
                    itemCount: _flatPlaylist.length,
                    itemBuilder: (context, i) {
                      final item = _flatPlaylist[i];
                      final isCurrent = (i == _playlistIndex);

                      // Draw a visual separator whenever moving into a new grouping block
                      final showTopDivider = i > 0 &&
                          _flatPlaylist[i - 1].entryIndex != item.entryIndex;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showTopDivider)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(color: Colors.white24, height: 1),
                            ),
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: isCurrent
                                ? BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                    ),
                                  )
                                : null,
                            child: Text(
                              item.text,
                              style: TextStyle(
                                fontSize: _fontSize,
                                color: isCurrent
                                    ? Colors.white
                                    : (item.isInput
                                        ? Colors.white30
                                        : Colors.white54),
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          _buildControls(context, l10n),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, AppLocalizations l10n) {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon:
                const Icon(Icons.skip_previous, color: Colors.white, size: 32),
            onPressed: _prevBlock,
            tooltip: 'Previous block',
          ),
          IconButton(
            icon: Icon(
              Icons.repeat_one,
              color: _repeatBlock ? Colors.blue.shade300 : Colors.white,
              size: 28,
            ),
            onPressed: _toggleRepeatBlock,
            tooltip: l10n.driveModeRepeatBlock,
          ),
          IconButton(
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
            onPressed: _playing
                ? () async {
                    await _pauseAudio();
                    if (mounted) setState(() => _playing = false);
                  }
                : () async {
                    await _resumeAudio();
                    if (mounted) setState(() => _playing = true);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
            onPressed: _goNextBlock,
            tooltip: 'Next block',
          ),
          IconButton(
            icon: const Icon(Icons.replay, color: Colors.white, size: 28),
            onPressed: _restartLesson,
            tooltip: 'Restart lesson',
          ),
        ],
      ),
    );
  }
}

enum _ItemResult {
  ok,
  error,
  cancelled,
}

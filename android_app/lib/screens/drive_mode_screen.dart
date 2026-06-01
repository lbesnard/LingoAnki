import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../l10n/app_localizations.dart';
import '../services/sync_service.dart';

import '../utils/web_audio.dart' as web;

/// Drive Mode screen: audio-first hands-free lesson playback.
///
/// Plays a sequential playlist of individual audio segment files per
/// **Sentence Block** (called "Block" in the UI).  Bold-highlights the
/// currently playing item.  Highlighting is driven by playlist index — no
/// pre-assembled MP3 or audio_timing values needed.
///
/// Playback engine:
/// * Web (Firefox / Chrome): a single persistent `HTMLAudioElement` driven
///   directly via `package:web`.  Each item is awaited via a per-item
///   `Completer` resolved on the `ended` DOM event.  This avoids
///   `just_audio_web`'s fire-and-forget auto-start inside `load()` which
///   loses the user-gesture authorisation between items.
/// * APK (Android / iOS): existing `just_audio` `AudioPlayer`, awaited
///   per-item via `processingStateStream.firstWhere(completed)`.
///
/// Both paths share a single linear async loop (`_runDriveMode`).  Manual
/// navigation cancels the loop via a generation counter.
class DriveModeScreen extends StatefulWidget {
  /// Lesson entries from PlayerScreen._sentenceEntries (already loaded).
  final List<Map<String, dynamic>> entries;

  /// Variant key e.g. 'original', 'enhanced', 'present', 'future'.
  final String variantKey;

  final String lessonTitle;

  /// Pause between segments in milliseconds (from server config).
  final int pauseMs;

  const DriveModeScreen({
    super.key,
    required this.entries,
    required this.variantKey,
    required this.lessonTitle,
    required this.pauseMs,
  });

  @override
  State<DriveModeScreen> createState() => _DriveModeScreenState();
}

/// One playable item inside a Sentence Block.
class _PlaylistItem {
  final int entryIndex;
  final int qaIndex; // -1 = sentence
  final bool isInput; // true = Input Language audio
  final bool isQuestion; // only meaningful when qaIndex >= 0
  final String audioPath; // relative path served by server
  final String text; // text to bold when this item is playing

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
  /// APK only: just_audio player.  Null on web.
  AudioPlayer? _player;

  /// Web only: bare HTMLAudioElement.  Null on APK.
  web.HTMLAudioElement? _webAudio;

  // ── UI state ──
  static const List<double> _fontSizes = [12.0, 14.0, 20.0, 26.0];
  double _fontSize = 26.0;

  late List<List<_PlaylistItem>> _blocks;
  int _blockIndex = 0;
  int _itemIndex = 0;
  bool _repeatBlock = false;
  bool _playing = false;

  // ── Auto-scroll mechanics ──
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _blockKeys = {};

  // ── Loop control ──
  /// Bumped every time the loop must be invalidated (manual navigation,
  /// dispose).  The running loop checks this after every await.
  int _generation = 0;

  /// Completer for the item currently being awaited inside `_playOne`.
  /// Completed by `ended` (success), by `error` (failure), or by manual
  /// navigation (cancellation).
  Completer<_ItemResult>? _currentItem;

  /// Active web listeners typed dynamically to satisfy both implementations
  dynamic _webEndedListener;
  dynamic _webErrorListener;

  // ── APK only ──
  /// Track which audio paths have been freshly downloaded this session.
  /// On first play of each path, force a re-download to flush stale cache.
  /// Not used on web (server URLs, no local cache).
  final Set<String> _refreshedPaths = {};

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webAudio = web.HTMLAudioElement();
      _webAudio!.preload = 'auto';
    } else {
      _player = AudioPlayer();
    }
    _blocks = _buildBlocks();
    if (_blocks.isNotEmpty) {
      _runDriveMode();
    }
  }

  @override
  void dispose() {
    _generation++; // invalidate any in-flight loop
    _currentItem?.complete(_ItemResult.cancelled);
    _detachWebListeners();
    _webAudio?.pause();
    _webAudio?.removeAttribute('src');
    _player?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Auto-scroll Helper ──────────────────────────────────────────────────────

  void _scrollToBlock(int idx) {
    // Post frame to make sure keys are drawn and layout bounds are updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _blockKeys[idx];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;

      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.3, // Anchor the item into the upper-middle frame view
      );
    });
  }

  // ── Build playlist ──────────────────────────────────────────────────────────

  List<List<_PlaylistItem>> _buildBlocks() {
    final blocks = <List<_PlaylistItem>>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final entry = widget.entries[i];
      final items = <_PlaylistItem>[];

      final sentencePath = (entry['sentence_audio_path'] as String?) ?? '';
      final sentenceInputPath =
          (entry['sentence_input_language_audio_path'] as String?) ?? '';
      final sentenceText = (entry['sentence'] as String?) ?? '';
      final sentenceInputText = (entry['sentence_input'] as String?) ?? '';

      if (sentenceInputPath.isNotEmpty) {
        items.add(_PlaylistItem(
          entryIndex: i,
          qaIndex: -1,
          isInput: true,
          isQuestion: false,
          audioPath: sentenceInputPath,
          text: sentenceInputText,
        ));
      }
      if (sentencePath.isNotEmpty) {
        items.add(_PlaylistItem(
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
          items.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: true,
            isQuestion: true,
            audioPath: qInputPath,
            text: qInputText,
          ));
        }
        if (qPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: false,
            isQuestion: true,
            audioPath: qPath,
            text: qText,
          ));
        }
        if (aInputPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: true,
            isQuestion: false,
            audioPath: aInputPath,
            text: aInputText,
          ));
        }
        if (aPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i,
            qaIndex: j,
            isInput: false,
            isQuestion: false,
            audioPath: aPath,
            text: aText,
          ));
        }
      }

      if (items.isEmpty) {
        debugPrint('[DriveMode] entry[$i] produced no playable items — '
            'upstream bug? all audio paths empty');
      } else {
        blocks.add(items);
      }
    }
    return blocks;
  }

  // ── Main loop ───────────────────────────────────────────────────────────────

  /// Linear advancement loop.  Cancelled by bumping `_generation` and
  /// completing `_currentItem`.
  Future<void> _runDriveMode() async {
    final gen = ++_generation;
    if (mounted) setState(() => _playing = true);

    if (_blocks.isNotEmpty) {
      _scrollToBlock(_blockIndex);
    }

    while (mounted && gen == _generation && _blockIndex < _blocks.length) {
      final block = _blocks[_blockIndex];
      int playCount = 0;

      while (mounted && gen == _generation && _itemIndex < block.length) {
        final item = block[_itemIndex];
        debugPrint('[DriveMode] play block[$_blockIndex] item[$_itemIndex] '
            '${item.audioPath}');

        final result = await _playOne(item);
        if (!mounted || gen != _generation) return;

        if (result == _ItemResult.error) {
          if (mounted) setState(() => _playing = false);
          return;
        }

        playCount++;

        // Only repeat if it's NOT an input language file (meaning it's a target
        // sentence, question, or answer) and it hasn't played twice yet.
        if (!item.isInput && playCount < 2) {
          await Future.delayed(Duration(milliseconds: widget.pauseMs));
          if (!mounted || gen != _generation) return;
          continue; // Loop again for the second play of this target audio
        }

        // Reset the count for the next playlist item
        playCount = 0;

        // Inter-segment pause. Skip after last item — _nextBlock has its own.
        if (_itemIndex + 1 < block.length) {
          await Future.delayed(Duration(milliseconds: widget.pauseMs));
          if (!mounted || gen != _generation) return;
          setState(() => _itemIndex++);
        } else {
          break; // exit inner loop, handle block transition below
        }
      }

      if (!mounted || gen != _generation) return;

      if (_repeatBlock) {
        await Future.delayed(Duration(milliseconds: widget.pauseMs));
        if (!mounted || gen != _generation) return;
        setState(() => _itemIndex = 0);
      } else {
        if (_blockIndex + 1 < _blocks.length) {
          await Future.delayed(Duration(milliseconds: widget.pauseMs * 2));
          if (!mounted || gen != _generation) return;
          setState(() {
            _blockIndex++;
            _itemIndex = 0;
          });
          _scrollToBlock(_blockIndex);
        } else {
          // Reached end of lesson.
          if (mounted) setState(() => _playing = false);
          return;
        }
      }
    }
  }

  /// Plays one item to completion.  Returns when audio fires `ended`,
  /// fails with `error`, or is cancelled by manual navigation.
  Future<_ItemResult> _playOne(_PlaylistItem item) async {
    final completer = Completer<_ItemResult>();
    _currentItem = completer;

    String? src;
    try {
      // On web `forceRefresh` is a no-op (server URL, no local file).
      final isFirstPlay = _refreshedPaths.add(item.audioPath);

      // Only force a network refresh check if we aren't trying to run offline
      final shouldRefresh = !kIsWeb && isFirstPlay;

      final uri = await SyncService.ensureLocalAndGetUri(
        item.audioPath,
        forceRefresh: shouldRefresh,
      ).catchError((e) {
        // Fallback fallback: if network validation throws because you are offline,
        // try to see if SyncService can still give you the local path directly.
        debugPrint(
            '[DriveMode] Offline fallback triggered for ${item.audioPath}');
        return Uri.parse(item.audioPath);
      });
      if (uri == null) {
        debugPrint('[DriveMode] ERROR: audio path resolved to null '
            '(${item.audioPath}) — upstream bug');
        if (!completer.isCompleted) completer.complete(_ItemResult.error);
        return completer.future;
      }
      src = uri.toString();
    } catch (e) {
      debugPrint('[DriveMode] ERROR: ensureLocalAndGetUri threw for '
          '${item.audioPath}: $e');
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

  // ── Web playback ────────────────────────────────────────────────────────────

  void _playOneWeb(String src, Completer<_ItemResult> completer) {
    final audio = _webAudio!;
    _detachWebListeners();

    void onEnded(web.Event _) {
      // Changed to proxy web.Event
      _detachWebListeners();
      if (!completer.isCompleted) completer.complete(_ItemResult.ok);
    }

    void onError(web.Event _) {
      // Changed to proxy web.Event
      final err = audio.error;
      debugPrint('[DriveMode] ERROR: HTMLAudioElement error '
          'code=${err?.code} msg="${err?.message}" src=$src');
      _detachWebListeners();
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
    }

    // Convert callbacks using the strict top-level wrapper functions
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

  // ── APK / native playback ───────────────────────────────────────────────────

// ── APK / native playback ───────────────────────────────────────────────────

  Future<void> _playOneNative(
      String src, Completer<_ItemResult> completer) async {
    final player = _player!;
    StreamSubscription<ProcessingState>? sub;

    try {
      // 1. Safe Native URI Parsing
      // If the path is a local file path (cached by SyncService), package it safely.
      Uri audioUri;
      if (src.startsWith('http://') || src.startsWith('https://')) {
        audioUri = Uri.parse(src);
      } else {
        audioUri = Uri.file(
            src); // Ensure local storage paths are treated as file:// schemes
      }

      // 2. Set the local source and completely await processing/buffering
      await player.setAudioSource(AudioSource.uri(audioUri));

      // If manual navigation bumped the generation counter while we loaded, exit.
      if (completer.isCompleted) return;

      // 3. Bind the state listener ONLY after loading is fully completed
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

      // 4. Play the track smoothly from local storage
      await player.play();
    } catch (e) {
      debugPrint('[DriveMode] ERROR: native playback threw for $src: $e');
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
    }

    // Guard against manual navigation cancellations resetting lifecycle hooks
    completer.future.whenComplete(() => sub?.cancel());
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

  /// Cancels the in-flight loop iteration so a fresh `_runDriveMode` can
  /// start at a new position.  Caller must update `_blockIndex` /
  /// `_itemIndex` before invoking `_runDriveMode` again.
  Future<void> _interruptForNavigation() async {
    _generation++;
    _currentItem?.complete(_ItemResult.cancelled);
    _currentItem = null;
    _detachWebListeners();
    await _stopAudio();
  }

  Future<void> _prevBlock() async {
    await _interruptForNavigation();
    final prev = _blockIndex > 0 ? _blockIndex - 1 : 0;
    setState(() {
      _blockIndex = prev;
      _itemIndex = 0;
    });
    _scrollToBlock(_blockIndex);
    _runDriveMode();
  }

  Future<void> _goNextBlock() async {
    await _interruptForNavigation();
    if (_blockIndex + 1 >= _blocks.length) {
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _blockIndex++;
      _itemIndex = 0;
    });
    _scrollToBlock(_blockIndex);
    _runDriveMode();
  }

  Future<void> _restartLesson() async {
    await _interruptForNavigation();
    setState(() {
      _blockIndex = 0;
      _itemIndex = 0;
    });
    _scrollToBlock(_blockIndex);
    _runDriveMode();
  }

  void _toggleRepeatBlock() {
    setState(() => _repeatBlock = !_repeatBlock);
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
    final totalBlocks = _blocks.length;
    final blockNum = totalBlocks > 0 ? _blockIndex + 1 : 0;

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
            child: _blocks.isEmpty
                ? Center(
                    child: Text(
                      l10n.driveModeAudioPending,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _blocks.length,
                    itemBuilder: (context, i) {
                      _blockKeys[i] ??= GlobalKey();
                      return Container(
                        key: _blockKeys[i],
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(12),
                        decoration: i == _blockIndex
                            ? BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              )
                            : null,
                        child: _buildBlockTextContent(i),
                      );
                    },
                  ),
          ),
          _buildControls(context, l10n),
        ],
      ),
    );
  }

  Widget _buildBlockTextContent(int index) {
    if (_blocks.isEmpty || index >= _blocks.length) {
      return const SizedBox();
    }
    final block = _blocks[index];
    final isCurrentBlock = index == _blockIndex;
    final currentItem = (isCurrentBlock && _itemIndex < block.length)
        ? block[_itemIndex]
        : null;
    final entry = widget.entries[index];

    final sentenceInputText = (entry['sentence_input'] as String?) ?? '';
    final sentenceText = (entry['sentence'] as String?) ?? '';
    final qaList = (entry['qa'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _styledText(
          sentenceInputText,
          bold: currentItem != null &&
              currentItem.qaIndex == -1 &&
              currentItem.isInput,
          isInput: true,
          dimmed: !isCurrentBlock,
        ),
        const SizedBox(height: 4),
        _styledText(
          sentenceText,
          bold: currentItem != null &&
              currentItem.qaIndex == -1 &&
              !currentItem.isInput,
          isInput: false,
          dimmed: !isCurrentBlock,
        ),
        if (qaList.isNotEmpty) ...[
          for (var j = 0; j < qaList.length; j++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(color: Colors.white24, height: 1),
            ),
            const SizedBox(height: 4),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['question_input']
                      as String? ??
                  '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  currentItem.isQuestion &&
                  currentItem.isInput,
              isInput: true,
              dimmed: !isCurrentBlock,
            ),
            const SizedBox(height: 4),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['question'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  currentItem.isQuestion &&
                  !currentItem.isInput,
              isInput: false,
              dimmed: !isCurrentBlock,
            ),
            const SizedBox(height: 8),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['answer_input'] as String? ??
                  '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  !currentItem.isQuestion &&
                  currentItem.isInput,
              isInput: true,
              dimmed: !isCurrentBlock,
            ),
            const SizedBox(height: 4),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['answer'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  !currentItem.isQuestion &&
                  !currentItem.isInput,
              isInput: false,
              dimmed: !isCurrentBlock,
            ),
          ],
        ],
      ],
    );
  }

  Widget _styledText(String text,
      {required bool bold, required bool isInput, required bool dimmed}) {
    if (text.isEmpty) return const SizedBox.shrink();

    Color textColor;
    if (bold) {
      textColor = Colors.white;
    } else if (dimmed) {
      textColor = isInput ? Colors.white24 : Colors.white30;
    } else {
      textColor = isInput ? Colors.white54 : Colors.white70;
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: _fontSize,
        color: textColor,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        height: 1.4,
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
                    setState(() => _playing = false);
                  }
                : () async {
                    await _resumeAudio();
                    setState(() => _playing = true);
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

/// Result of awaiting one playlist item.
enum _ItemResult {
  /// Audio played through and `ended` fired.
  ok,

  /// HTMLAudioElement / just_audio reported an error.  Loop must stop.
  error,

  /// Manual navigation cancelled the in-flight item.  Loop should bail
  /// without advancing — a fresh `_runDriveMode` is starting.
  cancelled,
}

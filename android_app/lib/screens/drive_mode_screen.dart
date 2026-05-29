import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:web/web.dart' as web;

import '../l10n/app_localizations.dart';
import '../services/sync_service.dart';

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
  final int qaIndex;      // -1 = sentence
  final bool isInput;     // true = Input Language audio
  final bool isQuestion;  // only meaningful when qaIndex >= 0
  final String audioPath; // relative path served by server
  final String text;      // text to bold when this item is playing

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

  // ── Loop control ──
  /// Bumped every time the loop must be invalidated (manual navigation,
  /// dispose).  The running loop checks this after every await.
  int _generation = 0;

  /// Completer for the item currently being awaited inside `_playOne`.
  /// Completed by `ended` (success), by `error` (failure), or by manual
  /// navigation (cancellation).
  Completer<_ItemResult>? _currentItem;

  /// Active web `ended`/`error` JS listeners (so we can remove them on
  /// each new item — `addEventListener` does not de-duplicate).
  JSFunction? _webEndedListener;
  JSFunction? _webErrorListener;

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
    _generation++;             // invalidate any in-flight loop
    _currentItem?.complete(_ItemResult.cancelled);
    _detachWebListeners();
    _webAudio?.pause();
    _webAudio?.removeAttribute('src');
    _player?.dispose();
    super.dispose();
  }

  // ── Build playlist ──────────────────────────────────────────────────────────

  List<List<_PlaylistItem>> _buildBlocks() {
    final blocks = <List<_PlaylistItem>>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final entry = widget.entries[i];
      final items = <_PlaylistItem>[];

      final sentencePath = (entry['sentence_audio_path'] as String?) ?? '';
      final sentenceInputPath = (entry['sentence_input_language_audio_path'] as String?) ?? '';
      final sentenceText = (entry['sentence'] as String?) ?? '';
      final sentenceInputText = (entry['sentence_input'] as String?) ?? '';

      if (sentenceInputPath.isNotEmpty) {
        items.add(_PlaylistItem(
          entryIndex: i, qaIndex: -1, isInput: true, isQuestion: false,
          audioPath: sentenceInputPath, text: sentenceInputText,
        ));
      }
      if (sentencePath.isNotEmpty) {
        items.add(_PlaylistItem(
          entryIndex: i, qaIndex: -1, isInput: false, isQuestion: false,
          audioPath: sentencePath, text: sentenceText,
        ));
      }

      final qaList = (entry['qa'] as List<dynamic>?) ?? [];
      for (var j = 0; j < qaList.length; j++) {
        final qa = qaList[j] as Map<String, dynamic>;
        final qPath = (qa['question_audio_path'] as String?) ?? '';
        final qInputPath = (qa['question_input_language_audio_path'] as String?) ?? '';
        final aPath = (qa['answer_audio_path'] as String?) ?? '';
        final aInputPath = (qa['answer_input_language_audio_path'] as String?) ?? '';
        final qText = (qa['question'] as String?) ?? '';
        final qInputText = (qa['question_input'] as String?) ?? '';
        final aText = (qa['answer'] as String?) ?? '';
        final aInputText = (qa['answer_input'] as String?) ?? '';

        if (qInputPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i, qaIndex: j, isInput: true, isQuestion: true,
            audioPath: qInputPath, text: qInputText,
          ));
        }
        if (qPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i, qaIndex: j, isInput: false, isQuestion: true,
            audioPath: qPath, text: qText,
          ));
        }
        if (aInputPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i, qaIndex: j, isInput: true, isQuestion: false,
            audioPath: aInputPath, text: aInputText,
          ));
        }
        if (aPath.isNotEmpty) {
          items.add(_PlaylistItem(
            entryIndex: i, qaIndex: j, isInput: false, isQuestion: false,
            audioPath: aPath, text: aText,
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
      final uri = await SyncService.ensureLocalAndGetUri(
        item.audioPath,
        forceRefresh: !kIsWeb && isFirstPlay,
      );
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

    final endedCb = onEnded.toJS;
    final errorCb = onError.toJS;
    _webEndedListener = endedCb;
    _webErrorListener = errorCb;
    audio.addEventListener('ended', endedCb);
    audio.addEventListener('error', errorCb);

    audio.src = src;
    // Calling play() returns a Promise.  Ignoring its result is fine —
    // success continues asynchronously, failure surfaces via the `error`
    // event listener above.
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

  Future<void> _playOneNative(String src, Completer<_ItemResult> completer) async {
    final player = _player!;
    StreamSubscription<ProcessingState>? sub;

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

    try {
      await player.setAudioSource(AudioSource.uri(Uri.parse(src)));
      await player.play();
    } catch (e) {
      debugPrint('[DriveMode] ERROR: native playback threw for $src: $e');
      sub.cancel();
      if (!completer.isCompleted) completer.complete(_ItemResult.error);
    }

    // Ensure the subscription is torn down if the completer resolved via
    // cancellation (manual nav) rather than the completed event.
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
    _runDriveMode();
  }

  Future<void> _restartLesson() async {
    await _interruptForNavigation();
    setState(() {
      _blockIndex = 0;
      _itemIndex = 0;
    });
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
                  : '\u2014',
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
                : _buildBlockText(context),
          ),
          _buildControls(context, l10n),
        ],
      ),
    );
  }

  Widget _buildBlockText(BuildContext context) {
    if (_blocks.isEmpty || _blockIndex >= _blocks.length) {
      return const SizedBox();
    }
    final block = _blocks[_blockIndex];
    final currentItem = _itemIndex < block.length ? block[_itemIndex] : null;
    final entry = widget.entries[_blockIndex];

    final sentenceInputText = (entry['sentence_input'] as String?) ?? '';
    final sentenceText = (entry['sentence'] as String?) ?? '';
    final qaList = (entry['qa'] as List<dynamic>?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _styledText(
            sentenceInputText,
            bold: currentItem != null && currentItem.qaIndex == -1 && currentItem.isInput,
            isInput: true,
          ),
          const SizedBox(height: 4),
          _styledText(
            sentenceText,
            bold: currentItem != null && currentItem.qaIndex == -1 && !currentItem.isInput,
            isInput: false,
          ),
          const SizedBox(height: 16),
          for (var j = 0; j < qaList.length; j++) ...[
            const Divider(color: Colors.grey),
            const SizedBox(height: 8),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['question_input'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  currentItem.isQuestion &&
                  currentItem.isInput,
              isInput: true,
            ),
            const SizedBox(height: 4),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['question'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  currentItem.isQuestion &&
                  !currentItem.isInput,
              isInput: false,
            ),
            const SizedBox(height: 8),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['answer_input'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  !currentItem.isQuestion &&
                  currentItem.isInput,
              isInput: true,
            ),
            const SizedBox(height: 4),
            _styledText(
              (qaList[j] as Map<String, dynamic>)['answer'] as String? ?? '',
              bold: currentItem != null &&
                  currentItem.qaIndex == j &&
                  !currentItem.isQuestion &&
                  !currentItem.isInput,
              isInput: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _styledText(String text, {required bool bold, required bool isInput}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        fontSize: _fontSize,
        color: bold
            ? Colors.white
            : isInput
                ? Colors.white54
                : Colors.white70,
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
            icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
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

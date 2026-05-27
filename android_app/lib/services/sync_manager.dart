import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_db_service.dart';
import 'sync_service.dart';

/// Global singleton that manages sync state across all screens.
/// Start a sync from any screen; progress is visible app-wide.
class SyncManager extends ChangeNotifier {
  SyncManager._();
  static final instance = SyncManager._();

  bool isSyncing = false;
  bool _cancelled = false;
  double? progress; // null = indeterminate, 0.0–1.0 = determinate
  String message = '';
  int filesDownloaded = 0;

  void cancel() {
    _cancelled = true;
  }

  Future<void> syncLesson(String base) async {
    if (isSyncing) return;
    _start('Loading manifest…');
    try {
      await _syncPendingLessonReviews();
      await _syncPendingDiaryEntries();
      await _syncPendingScores();
      final count = await SyncService.syncLesson(
        base,
        onProgress: (msg) {
          message = msg;
          notifyListeners();
        },
        onProgressCount: (current, total) {
          progress = total > 0 ? current / total : 1.0;
          message = '$current / $total';
          notifyListeners();
        },
        isCancelled: () => _cancelled,
      );
      filesDownloaded = count;
      message = _cancelled ? 'Cancelled.' : 'Synced $count file(s) ✓';
      progress = 1.0;
      notifyListeners();
    } catch (e) {
      message = 'Sync failed: $e';
      progress = null;
      notifyListeners();
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncAll({void Function(String)? onProgress}) async {
    if (isSyncing) return;
    _start('Loading manifest…');
    try {
      await _syncPendingLessonReviews();
      await _syncPendingDiaryEntries();
      await _syncPendingScores();
      if (kIsWeb) {
        // Web: audio streams directly from server, no local caching needed.
        message = 'Web mode — audio streams from server ✓';
        progress = 1.0;
        notifyListeners();
      } else {
        final count = await SyncService.syncFromServer(
          onProgress: (msg) {
            message = msg;
            notifyListeners();
          },
          onProgressCount: (current, total) {
            progress = total > 0 ? current / total : 1.0;
            message = '$current / $total';
            notifyListeners();
          },
          isCancelled: () => _cancelled,
        );
        filesDownloaded = count;
        message = _cancelled ? 'Cancelled.' : 'Synced $count file(s) ✓';
        progress = 1.0;
        notifyListeners();
      }
    } catch (e) {
      message = 'Sync failed: $e';
      progress = null;
      notifyListeners();
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  void _start(String initialMessage) {
    isSyncing = true;
    _cancelled = false;
    progress = null;
    message = initialMessage;
    filesDownloaded = 0;
    notifyListeners();
  }

  /// Sync pending lesson last_reviewed timestamps to server
  Future<void> _syncPendingLessonReviews() async {
    final pending = await LocalDbService.getUnsyncedLessonReviews();
    for (final row in pending) {
      if (_cancelled) break;
      try {
        final date = row['date'] as String;
        final timestamp = row['last_reviewed'] as String;
        await ApiService.updateLessonLastReviewed(date, timestamp: timestamp);
        await LocalDbService.markLessonReviewSynced(date);
      } catch (e) {
        if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
          break; // Network unreachable — retry on next sync
        }
        debugPrint('SyncManager: lesson review sync failed for ${row['date']}: $e');
      }
    }
  }

  /// Replay any locally saved scores that weren't sent to the server yet.
  /// Continues past individual failures so all pending scores are attempted.
  Future<void> _syncPendingScores() async {
    final pending = await LocalDbService.getUnsyncedScores();
    for (final row in pending) {
      if (_cancelled) break;
      try {
        await ApiService.scoreEntry(
          row['date'] as String,
          row['entry_index'] as int,
          row['score'] as int,
        );
        await LocalDbService.markScoreSynced(row['id'] as int);
      } catch (e) {
        // Network unreachable or other error — no point continuing, try again on next sync.
        if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
          break;
        }
        // Log but continue so remaining scores are still attempted.
        debugPrint('SyncManager: score sync failed for row ${row['id']}: $e');
      }
    }
  }

  /// Replay any locally saved diary entries that weren't sent to the server yet.
  Future<void> _syncPendingDiaryEntries() async {
    final pending = await LocalDbService.getUnsyncedDiaryEntries();
    for (final row in pending) {
      if (_cancelled) break;
      final id = row['id'] as int;
      final date = row['date'] as String;
      final sentences = row['sentences'] as List<String>;
      try {
        await ApiService.addSentences(date, sentences);
        await LocalDbService.markDiarySynced(id);
      } catch (e) {
        if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
          break; // Network unreachable — retry on next sync.
        }
        debugPrint('SyncManager: diary entry sync failed for row $id: $e');
      }
    }
  }
}

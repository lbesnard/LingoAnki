import 'package:flutter/foundation.dart';
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
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class SyncService {
  /// Returns the local directory used to cache synced output files.
  static Future<Directory> _localOutputDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/output');
    await dir.create(recursive: true);
    return dir;
  }

  /// Returns the full local path for a given relative output file path.
  static Future<String> localPath(String relPath) async {
    final dir = await _localOutputDir();
    return '${dir.path}/$relPath';
  }

  /// Syncs all output files from the server.
  /// Downloads files that are missing or have a newer mtime on the server.
  /// Returns the number of files downloaded.
  static Future<int> syncFromServer({
    void Function(String message)? onProgress,
    void Function(int current, int total)? onProgressCount,
    bool Function()? isCancelled,
  }) async {
    final dir = await _localOutputDir();
    final manifest = await ApiService.getSyncManifest();
    final total = manifest.length;
    int checked = 0;
    int downloaded = 0;

    for (final entry in manifest) {
      if (isCancelled != null && isCancelled()) break;
      checked++;
      final relPath = entry['path'] as String;
      final serverMtime = (entry['mtime'] as num).toDouble();
      final localFile = File('${dir.path}/$relPath');

      bool needsDownload = true;
      if (await localFile.exists()) {
        final localMtime = (await localFile.lastModified()).millisecondsSinceEpoch / 1000.0;
        if (localMtime >= serverMtime) needsDownload = false;
      }

      if (needsDownload) {
        onProgress?.call('Downloading $relPath …');
        final resp = await ApiService.downloadFile(relPath);
        if (resp.statusCode == 200) {
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(resp.bodyBytes);
          downloaded++;
        }
      }
      onProgressCount?.call(checked, total);
    }
    return downloaded;
  }

  /// Syncs files for a single lesson (filtered by base name).
  static Future<int> syncLesson(
    String base, {
    void Function(String message)? onProgress,
    void Function(int current, int total)? onProgressCount,
    bool Function()? isCancelled,
  }) async {
    final dir = await _localOutputDir();
    final manifest = await ApiService.getLessonManifest(base);
    final total = manifest.length;
    int checked = 0;
    int downloaded = 0;

    for (final entry in manifest) {
      if (isCancelled != null && isCancelled()) break;
      checked++;
      final relPath = entry['path'] as String;
      final serverMtime = (entry['mtime'] as num).toDouble();
      final localFile = File('${dir.path}/$relPath');

      bool needsDownload = true;
      if (await localFile.exists()) {
        final localMtime = (await localFile.lastModified()).millisecondsSinceEpoch / 1000.0;
        if (localMtime >= serverMtime) needsDownload = false;
      }

      if (needsDownload) {
        onProgress?.call('Downloading $relPath …');
        final resp = await ApiService.downloadFile(relPath);
        if (resp.statusCode == 200) {
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(resp.bodyBytes);
          downloaded++;
        }
      }
      onProgressCount?.call(checked, total);
    }
    return downloaded;
  }

  /// Lists locally cached lesson mp3 files.
  static Future<List<FileSystemEntity>> listLocalMp3s() async {
    final dir = await _localOutputDir();
    if (!await dir.exists()) return [];
    return dir
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.mp3'))
        .toList();
  }
}

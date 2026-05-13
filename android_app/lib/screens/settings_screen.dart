import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _username = '';
  String _serverUrl = '';
  String _cacheSize = '…';
  late TextEditingController _serverController;
  bool _saving = false;
  bool _clearing = false;
  bool _loopDefault = false;
  bool _cycleVariants = false;
  bool _forceTimingRegen = false;

  // Tracks which maintenance job is currently running (null = none)
  String? _maintenanceRunning;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final username = await AuthService.getUsername() ?? '';
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? '';
    final cacheSize = await _computeCacheSize();
    setState(() {
      _username = username;
      _serverUrl = serverUrl;
      _serverController.text = serverUrl;
      _cacheSize = cacheSize;
      _loopDefault = prefs.getBool('lesson_loop_default') ?? false;
      _cycleVariants = prefs.getBool('lesson_cycle_variants') ?? false;
    });
  }

  Future<String> _computeCacheSize() async {
    if (kIsWeb) return 'N/A';
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${docsDir.path}/output');
      if (!await outputDir.exists()) return '0 B';
      int total = 0;
      await for (final entity in outputDir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      if (total < 1024) return '$total B';
      if (total < 1024 * 1024) {
        return '${(total / 1024).toStringAsFixed(1)} KB';
      }
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '—';
    }
  }

  Future<void> _saveServerUrl() async {
    final l10n = AppLocalizations.of(context);
    final url = _serverController.text.trim();
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    setState(() {
      _serverUrl = url;
      _saving = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsServerUpdated)),
      );
    }
  }

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.settingsSignOutTitle),
        content: Text(l10n.settingsSignOutBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancelButton)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.settingsSignOut)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AuthService.clearSession();
    if (mounted) context.go('/login');
  }

  Future<void> _clearCachedData() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.settingsClearDataTitle),
        content: Text(l10n.settingsClearDataBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancelButton)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      // 1. Delete all synced output files (Android only)
      if (!kIsWeb) {
        final docsDir = await getApplicationDocumentsDirectory();
        final outputDir = Directory('${docsDir.path}/output');
        if (await outputDir.exists()) {
          await outputDir.delete(recursive: true);
        }
      }

      // 2. Clear SQLite cache tables
      await LocalDbService.clearAll();

      // 3. Clear TPRS keyword prefs (they'll be re-fetched on next login)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('tprs_sentence');
      await prefs.remove('tprs_question');
      await prefs.remove('tprs_answer');

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final newSize = await _computeCacheSize();
        setState(() => _cacheSize = newSize);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsDataCleared)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.settingsErrorClearing(e.toString())),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// Run a named maintenance job; shows spinner + SnackBar feedback.
  Future<void> _runMaintenanceJob(
      String jobKey, Future<void> Function() call) async {
    if (_maintenanceRunning != null) return;
    setState(() => _maintenanceRunning = jobKey);
    try {
      await call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Started — this may take several minutes'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _maintenanceRunning = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // ── Account ───────────────────────────────────────────────────────
          _sectionHeader(l10n.settingsAccount),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.settingsUsernameLabel),
            subtitle: Text(_username.isEmpty ? '—' : _username),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(l10n.settingsServerLabel),
            subtitle: Text(_serverUrl.isEmpty ? '—' : _serverUrl),
          ),
          const Divider(),

          // ── Server URL ────────────────────────────────────────────────────
          _sectionHeader(l10n.settingsChangeServer),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      labelText: l10n.loginServerUrl,
                      hintText: l10n.loginServerHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _saveServerUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _saveServerUrl,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.settingsSave),
                ),
              ],
            ),
          ),
          const Divider(),

          // ── Lesson playback ───────────────────────────────────────────────
          _sectionHeader('Lesson playback'),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('Auto-repeat lesson'),
            subtitle: const Text(
                'Start each lesson with the repeat loop enabled by default'),
            value: _loopDefault,
            onChanged: (v) async {
              setState(() => _loopDefault = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('lesson_loop_default', v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.playlist_play),
            title: const Text('Auto-cycle all variants'),
            subtitle: const Text(
                'When a variant finishes, automatically play the next one: '
                'Original → Enhanced → Present → Future, then stop'),
            value: _cycleVariants,
            onChanged: (v) async {
              setState(() => _cycleVariants = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('lesson_cycle_variants', v);
            },
          ),
          const Divider(),

          // ── Maintenance ───────────────────────────────────────────────────
          _sectionHeader('Maintenance'),
          // "Fix everything" — primary action
          ListTile(
            leading: _maintenanceRunning == 'all'
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.build_circle,
                    color: Theme.of(context).colorScheme.primary),
            title: const Text('Fix everything'),
            subtitle: const Text(
                'Sync diary, fill missing Q&A and rebuild audio timing in one go'),
            onTap: _maintenanceRunning != null
                ? null
                : () => _runMaintenanceJob(
                    'all', ApiService.triggerBackfillAll),
          ),
          ListTile(
            leading: _maintenanceRunning == 'qa'
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.translate),
            title: const Text('Fill missing Q&A translations'),
            subtitle: const Text(
                'Generates Q&A pairs not yet translated into your study language'),
            onTap: _maintenanceRunning != null
                ? null
                : () => _runMaintenanceJob(
                    'qa', ApiService.triggerQaTranslationBackfill),
          ),
          ListTile(
            leading: _maintenanceRunning == 'timing'
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.timer_outlined),
            title: const Text('Rebuild audio timing'),
            subtitle: const Text(
                'Recomputes sentence-highlight sync for all lessons'),
            onTap: _maintenanceRunning != null
                ? null
                : () => _runMaintenanceJob(
                    'timing',
                    () => ApiService.triggerAudioTimingBackfill(
                        overwrite: _forceTimingRegen)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.replay_outlined),
            title: const Text('Force audio re-generation'),
            subtitle: const Text(
                'Re-runs TTS for every lesson (slow). Leave off to only recompute timing from existing files.'),
            value: _forceTimingRegen,
            onChanged: _maintenanceRunning != null
                ? null
                : (v) => setState(() => _forceTimingRegen = v),
          ),
          const Divider(),

          // ── Sign out ──────────────────────────────────────────────────────
          _sectionHeader(l10n.settingsSession),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: Text(l10n.settingsSignOut),
            subtitle: Text(l10n.settingsSignOutSubtitle),
            onTap: _signOut,
          ),
          const Divider(),

          // ── Data ──────────────────────────────────────────────────────────
          _sectionHeader(l10n.settingsData),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.settingsStorageLabel),
            subtitle: Text(_cacheSize),
          ),
          ListTile(
            leading: _clearing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            title: Text(l10n.settingsClearData,
                style: const TextStyle(color: Colors.red)),
            subtitle: Text(l10n.settingsClearDataSubtitle),
            onTap: _clearing ? null : _clearCachedData,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

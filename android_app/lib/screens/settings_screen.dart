import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import 'login_screen.dart';

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
    });
  }

  Future<String> _computeCacheSize() async {
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
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
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
      // 1. Delete all synced output files
      final docsDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${docsDir.path}/output');
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
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

  // ── build ─────────────────────────────────────────────────────────────────────

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

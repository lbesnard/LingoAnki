import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    setState(() {
      _username = username;
      _serverUrl = serverUrl;
      _serverController.text = serverUrl;
    });
  }

  Future<void> _saveServerUrl() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    setState(() {
      _serverUrl = url;
      _saving = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL updated')),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
            'Your locally cached lessons and diary data will be kept.\n\nSign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all cached data'),
        content: const Text(
            'This will delete all downloaded lesson files (audio + text) and '
            'the local database cache.\n\n'
            'You will remain signed in and can sync again from the server.\n\n'
            'This cannot be undone. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All cached data cleared.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error clearing data: $e'),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Account ───────────────────────────────────────────────────────
          _sectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Username'),
            subtitle: Text(_username.isEmpty ? '—' : _username),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(_serverUrl.isEmpty ? '—' : _serverUrl),
          ),
          const Divider(),

          // ── Server URL ────────────────────────────────────────────────────
          _sectionHeader('Change server URL'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://192.168.1.x:8084',
                      border: OutlineInputBorder(),
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
                      : const Text('Save'),
                ),
              ],
            ),
          ),
          const Divider(),

          // ── Sign out ──────────────────────────────────────────────────────
          _sectionHeader('Session'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: const Text('Sign out'),
            subtitle: const Text('Keeps all cached data on this device'),
            onTap: _signOut,
          ),
          const Divider(),

          // ── Data ──────────────────────────────────────────────────────────
          _sectionHeader('Data'),
          ListTile(
            leading: _clearing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            title: const Text('Clear all cached data',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text(
                'Deletes downloaded lessons & diary cache from this device'),
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

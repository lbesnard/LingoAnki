import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/local_db_service.dart';
import '../services/sync_manager.dart';

class TranslationAttemptScreen extends StatefulWidget {
  final String date;
  final List<String> sentences;

  const TranslationAttemptScreen({
    super.key,
    required this.date,
    required this.sentences,
  });

  @override
  State<TranslationAttemptScreen> createState() => _TranslationAttemptScreenState();
}

class _TranslationAttemptScreenState extends State<TranslationAttemptScreen> {
  late final List<TextEditingController> _controllers;
  bool _saving = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _controllers = widget.sentences.map((_) => TextEditingController()).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAttempts() async {
    final l10n = AppLocalizations.of(context);
    final trials = _controllers.map((c) => c.text.trim()).toList();

    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });

    // Save to local queue first (offline-safe)
    await LocalDbService.savePendingTrials(widget.date, trials);

    // If online, trigger a flush (non-blocking)
    if (SyncManager.instance.isOnline) {
      SyncManager.instance.flushPending(); // fire and forget
    }

    if (mounted) {
      setState(() {
        _successMessage = SyncManager.instance.isOnline
            ? l10n.translationAttemptSaved
            : l10n.translationAttemptSavedLocally;
        _saving = false;
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translationAttemptTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.translationAttemptSkip,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.sentences.length,
              itemBuilder: (ctx, i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}. ${widget.sentences[i]}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _controllers[i],
                        decoration: InputDecoration(
                          hintText: l10n.translationAttemptHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        textInputAction: i < widget.sentences.length - 1
                            ? TextInputAction.next
                            : TextInputAction.done,
                        maxLines: null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_successMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_successMessage!,
                  style: TextStyle(color: Colors.green.shade800)),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_error!,
                  style: TextStyle(color: Colors.orange.shade900)),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.translationAttemptSkip),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveAttempts,
                    icon: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(l10n.saveAttemptsButton),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

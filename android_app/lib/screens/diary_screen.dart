import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  // Step: 1 = pick date, 2 = add sentences
  int _step = 1;
  DateTime _selectedDate = DateTime.now();
  final List<String> _sentences = [];
  final _sentenceController = TextEditingController();

  bool _saving = false;
  bool _generating = false;
  String? _generateLog;
  String? _error;
  String? _successMessage;

  // ── date picker ──────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _step = 2;
        _sentences.clear();
        _successMessage = null;
        _error = null;
      });
    }
  }

  void _addSentence() {
    final text = _sentenceController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sentences.add(text));
    _sentenceController.clear();
  }

  void _removeSentence(int index) {
    setState(() => _sentences.removeAt(index));
  }

  // ── save to server ────────────────────────────────────────────────────────────

  Future<void> _saveEntry() async {
    if (_sentences.isEmpty) {
      setState(() => _error = 'Add at least one sentence first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    try {
      await ApiService.addDiaryEntry(dateStr, List.from(_sentences));
      // Also cache locally
      final entryText = _sentences.map((s) => '- $s').join('\n');
      await LocalDbService.saveDiaryContent('[$dateStr]\n$entryText');
      setState(() {
        _successMessage = '✓ Entry saved for $dateStr (${_sentences.length} sentence(s))';
        _step = 1;
        _sentences.clear();
      });
    } catch (e) {
      // Save locally even when offline
      final entryText = _sentences.map((s) => '- $s').join('\n');
      await LocalDbService.saveDiaryContent('[$dateStr]\n$entryText');
      setState(() => _error = 'Saved locally (offline). Will sync when connected.\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── generate lessons ─────────────────────────────────────────────────────────

  Future<void> _generateLessons() async {
    setState(() {
      _generating = true;
      _generateLog = 'Starting generation…';
      _error = null;
    });
    try {
      await ApiService.triggerGenerate();
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 5));
        final log = await ApiService.getGenerateStatus();
        setState(() => _generateLog = log);
        if (log.contains('Done') || log.contains('Finished') || log.contains('Error')) break;
      }
    } catch (e) {
      setState(() => _error = 'Could not connect to server.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _sentenceController.dispose();
    super.dispose();
  }

  String get _dateLabel =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Step 1: Date selection ─────────────────────────────────────────
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.indigo),
              title: const Text('Diary date'),
              subtitle: Text(_dateLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: TextButton(
                onPressed: _pickDate,
                child: Text(_step == 1 ? 'Select date →' : 'Change'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Step 2: Sentences ─────────────────────────────────────────────
          if (_step == 2) ...[
            Text('Sentences for $_dateLabel',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sentenceController,
                    decoration: const InputDecoration(
                      hintText: 'Type a sentence…',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addSentence(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addSentence,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_sentences.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No sentences yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _sentences.length,
                itemBuilder: (ctx, i) => Dismissible(
                  key: ValueKey('$i-${_sentences[i]}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red.shade100,
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  onDismissed: (_) => _removeSentence(i),
                  child: ListTile(
                    dense: true,
                    leading: Text('${i + 1}.',
                        style: const TextStyle(color: Colors.grey)),
                    title: Text(_sentences[i]),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeSentence(i),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _saving ? null : _saveEntry,
              icon: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('Save to Server'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
          ],

          // ── Success / Error messages ───────────────────────────────────────
          if (_successMessage != null)
            Container(
              padding: const EdgeInsets.all(10),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_error!,
                  style: TextStyle(color: Colors.orange.shade900)),
            ),

          const Divider(height: 32),

          // ── Generate Lessons ──────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _generating ? null : _generateLessons,
            icon: _generating
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: const Text('Generate Lessons'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
          ),

          if (_generateLog != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(_generateLog!,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

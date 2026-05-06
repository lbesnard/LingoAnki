import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _homeData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Show cached data first for instant response
    final cached = await LocalDbService.getCachedHomeData();
    if (cached != null && mounted) {
      setState(() {
        _homeData = cached;
        _loading = false;
      });
    }

    // Refresh from server
    try {
      final data = await ApiService.getHomeData();
      await LocalDbService.saveHomeData(data);
      if (mounted) {
        setState(() {
          _homeData = data;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _homeData == null) {
        setState(() {
          _loading = false;
          _error = 'Server unreachable — no cached data.';
        });
      }
    }
  }

  Future<void> _onRefresh() => _loadData();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _homeData == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _loadData();
                },
                child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsCard(),
          const SizedBox(height: 12),
          if (_homeData?['recommended'] != null) ...[
            _buildRecommendationCard(),
            const SizedBox(height: 12),
          ],
          _buildRecentLessonsCard(),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final stats = _homeData?['stats'] as Map<String, dynamic>? ?? {};
    final total = (stats['total'] as int?) ?? 0;
    final mastered = (stats['mastered'] as int?) ?? 0;
    final learning = (stats['learning'] as int?) ?? 0;
    final newCount = (stats['new'] as int?) ?? 0;

    final masteredFrac = total > 0 ? mastered / total : 0.0;
    final learningFrac = total > 0 ? learning / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _progressRow(
              label: 'Mastered',
              count: mastered,
              total: total,
              value: masteredFrac,
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            _progressRow(
              label: 'In progress',
              count: learning,
              total: total,
              value: learningFrac,
              color: Colors.orange,
            ),
            const SizedBox(height: 8),
            Text(
              '$newCount new • $total total entries',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressRow({
    required String label,
    required int count,
    required int total,
    required double value,
    required Color color,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: value,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count/$total',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard() {
    final rec = _homeData!['recommended'] as Map<String, dynamic>;
    final title = rec['title'] as String? ?? rec['date'] as String? ?? '?';
    final variant = rec['variant'] as String? ?? 'original';
    final reason = rec['reason'] as String? ?? '';
    final reasonLabel = reason == 'due_for_review' ? 'Due for review' : 'New lesson';

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin, size: 18),
                const SizedBox(width: 6),
                Text('Study Now',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              '$variant · $reasonLabel',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.headphones, size: 16),
                label: const Text('Open'),
                onPressed: () => _openRecommended(rec),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLessonsCard() {
    final recent =
        (_homeData?['recent_lessons'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Lessons',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            if (recent.isEmpty)
              const Text('No lessons reviewed yet.',
                  style: TextStyle(color: Colors.grey))
            else
              ...recent.map((item) => _recentTile(item)),
          ],
        ),
      ),
    );
  }

  Widget _recentTile(Map<String, dynamic> item) {
    final date = item['date'] as String? ?? '';
    final title = item['title'] as String? ?? date;
    final status = item['status'] as String? ?? 'new';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'mastered':
        statusColor = Colors.green;
        statusIcon = Icons.star;
        break;
      case 'learning':
        statusColor = Colors.orange;
        statusIcon = Icons.check_circle_outline;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(statusIcon, color: statusColor, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _openFromRecent(item),
    );
  }

  Future<void> _openRecommended(Map<String, dynamic> rec) async {
    // Try to find the lesson in the lessons list and navigate to player
    try {
      final lessons = await ApiService.getLessons();
      final date = (rec['date'] as String? ?? '').replaceAll('/', '-');
      final match = lessons.cast<Map<String, dynamic>?>().firstWhere(
        (l) => (l?['base'] as String? ?? '').contains(date),
        orElse: () => null,
      );
      if (match != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlayerScreen(lesson: match)),
        );
      }
    } catch (_) {}
  }

  Future<void> _openFromRecent(Map<String, dynamic> item) async {
    try {
      final lessons = await ApiService.getLessons();
      final date = (item['date'] as String? ?? '').replaceAll('/', '-');
      final match = lessons.cast<Map<String, dynamic>?>().firstWhere(
        (l) => (l?['base'] as String? ?? '').contains(date),
        orElse: () => null,
      );
      if (match != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlayerScreen(lesson: match)),
        );
      }
    } catch (_) {}
  }
}

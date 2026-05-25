import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
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
    print('[DEBUG] HomeScreen._loadData: starting');
    // Show cached data first for instant response
    final cached = await LocalDbService.getCachedHomeData();
    print('[DEBUG] HomeScreen._loadData: cached=${cached == null ? 'null' : 'present'}');
    if (cached != null && mounted) {
      setState(() {
        _homeData = cached;
        _loading = false;
      });
    }

    // Refresh from server
    try {
      print('[DEBUG] HomeScreen._loadData: fetching from server');
      final data = await ApiService.getHomeData();
      print('[DEBUG] HomeScreen._loadData: server fetch succeeded');
      await LocalDbService.saveHomeData(data);
      if (mounted) {
        setState(() {
          _homeData = data;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('[DEBUG] HomeScreen._loadData: server fetch failed: $e');
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
          if (_isNewUser()) ...[
            _buildOnboardingCard(),
            const SizedBox(height: 12),
          ] else ...[
            _buildStatsCard(),
            const SizedBox(height: 12),
          ],
          if (_homeData?['recommended'] != null) ...[
            _buildRecommendationCard(),
            const SizedBox(height: 12),
          ],
          _buildRecentLessonsCard(),
        ],
      ),
    );
  }

  bool _isNewUser() {
    final stats = _homeData?['stats'] as Map<String, dynamic>? ?? {};
    final total = (stats['total'] as int?) ?? 0;
    return total == 0;
  }

  Widget _buildOnboardingCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.waving_hand,
                    color: Theme.of(context).colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  l10n.homeWelcomeTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(l10n.homeWelcomeBody,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.homeWelcomeTip,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(l10n.homeGoDiary),
                onPressed: () => context.go('/diary'),
              ),
            ),
          ],
        ),
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

    return InkWell(
      onTap: () {
        // Default to original review when clicking the card
        context.pushNamed('review');
      },
      child: Card(
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
                  Expanded(
                    child: Text('Study Now',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Review options',
                    icon: const Icon(Icons.headphones, size: 16),
                    onSelected: (value) {
                      if (value == 'original') {
                        context.pushNamed('review');
                      } else if (value == 'translation') {
                        context.pushNamed('nativeFirstReview');
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'original',
                        child: ListTile(
                          leading: Icon(Icons.rate_review_outlined),
                          title: Text('Original Review'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'translation',
                        child: ListTile(
                          leading: Icon(Icons.translate_outlined),
                          title: Text('Translation Excercise'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                    position: PopupMenuPosition.under, // closest to dropup, but Flutter default is dropdown
                    // For true dropup, a custom widget is needed; this is visually consistent
                  ),
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
            ],
          ),
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
            Text('Recently Studied',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            if (recent.isEmpty)
              const Text('No lessons studied yet.',
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
    final lastReviewed = item['last_reviewed'] as String? ?? '';
    final entryCount = item['entry_count'] as int? ?? 0;

    // Format the last reviewed time
    String timeAgo = '';
    if (lastReviewed.isNotEmpty) {
      try {
        final reviewTime = DateTime.parse(lastReviewed);
        final now = DateTime.now();
        final diff = now.difference(reviewTime);

        if (diff.inDays > 0) {
          timeAgo = '${diff.inDays}d ago';
        } else if (diff.inHours > 0) {
          timeAgo = '${diff.inHours}h ago';
        } else if (diff.inMinutes > 0) {
          timeAgo = '${diff.inMinutes}m ago';
        } else {
          timeAgo = 'Just now';
        }
      } catch (_) {
        timeAgo = '';
      }
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.play_circle_outline, color: Colors.blue, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '$date${timeAgo.isNotEmpty ? ' • $timeAgo' : ''}${entryCount > 0 ? ' • $entryCount sentences' : ''}',
        style: const TextStyle(fontSize: 11, color: Colors.grey)
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _openFromRecent(item),
    );
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

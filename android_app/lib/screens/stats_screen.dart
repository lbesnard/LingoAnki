import 'package:flutter/material.dart';

import '../services/local_db_service.dart';
import '../l10n/app_localizations.dart';

/// Review statistics and streak screen.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  static const _scoreColors = {
    0: Colors.red,
    2: Colors.orange,
    3: Colors.blue,
    5: Colors.green,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await LocalDbService.getReviewStats();
    if (mounted) setState(() { _stats = stats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStreakCard(),
                  const SizedBox(height: 16),
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  _buildDistributionCard(),
                ],
              ),
            ),
    );
  }

  Map<int, String> _localScoreLabels(AppLocalizations l10n) => {
    0: l10n.scoreAgain,
    2: l10n.scoreHard,
    3: l10n.scoreGood,
    5: l10n.scoreEasy,
  };

  Widget _buildStreakCard() {
    final l10n = AppLocalizations.of(context);
    final streak = _stats['streak'] as int? ?? 0;
    final today = _stats['today'] as int? ?? 0;
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              '🔥 $streak',
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dayStreak,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            if (today > 0) ...[
              const SizedBox(height: 12),
              Chip(
                label: Text(
                  l10n.reviewedToday(today),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade100,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Chip(
                label: Text(
                  l10n.noReviewsToday,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.grey.shade100,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final l10n = AppLocalizations.of(context);
    final total = _stats['total'] as int? ?? 0;
    final today = _stats['today'] as int? ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.statsOverview,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _statRow(l10n.statsTotalReviews, '$total'),
            _statRow(l10n.statsReviewedTodayLabel, '$today'),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionCard() {
    final l10n = AppLocalizations.of(context);
    final dist = (_stats['distribution'] as Map<int, int>?) ?? {};
    final total = dist.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.statsNoScores),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.statsScoreDistribution,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._scoreColors.entries.map((entry) {
              final score = entry.key;
              final color = entry.value;
              final label = _localScoreLabels(l10n)[score] ?? '$score';
              final count = dist[score] ?? 0;
              final fraction = total > 0 ? count / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w500,
                            )),
                        Text('$count (${(fraction * 100).round()}%)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            )),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

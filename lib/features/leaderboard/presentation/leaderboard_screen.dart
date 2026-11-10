import '../../../shared/arena_motion.dart';
import '../../../shared/arena_panel.dart';
import '../data/standings_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/campus_widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';
import '../../profile/domain/rank_tier.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.dataLoader});
  final Future<Map<String, dynamic>> Function(String type)? dataLoader;
  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardState();
}

class _LeaderboardState extends ConsumerState<LeaderboardScreen> {
  String type = 'weekly', arenaPeriod = 'weekly';
  late Future<Map<String, dynamic>> future;
  Map<String, dynamic>? cached;
  late final VoidCallback stopListening;
  @override
  void initState() {
    super.initState();
    final changes = ref.read(sessionProvider).dataChanges;
    changes.addListener(onDataChanged);
    stopListening = () => changes.removeListener(onDataChanged);
    load();
  }

  void onDataChanged() {
    if (mounted) setState(load);
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  void load() {
    final session = ref.read(sessionProvider);
    final cache = ref.read(standingsCacheProvider);
    final key = 'standings:${session.profile!.id}:$type';
    final period = cache.period(type, DateTime.now());
    cached = cache.read(key, period);
    final request = cache.begin(key);
    final fetched =
        widget.dataLoader?.call(type) ??
        (session.preview
            ? Future.value({
                'rows': [
                  for (final entry in [
                    ('one', 'Ananya Nair', 1840, 320),
                    ('two', 'Arjun Menon', 1760, 290),
                    ('three', 'Meera Iyer', 1680, 275),
                    ('preview', 'Alex Learner', 1240, 250),
                    ('five', 'Devika Das', 1190, 220),
                    ('six', 'Rahul Sharma', 1150, 190),
                  ].indexed)
                    {
                      'id': entry.$2.$1,
                      'full_name': entry.$2.$2,
                      'rating': entry.$2.$3,
                      'metric': type == 'all_time' ? entry.$2.$3 : entry.$2.$4,
                      'rank': entry.$1 + 1,
                      'level': 3,
                    },
                ],
              })
            : QuizRepository(session).rpc('get_leaderboard', {'type': type}));
    future = fetched.then((data) async {
      await cache.write(key, period, request, data);
      return data;
    });
  }

  void select(String value) => setState(() {
    type = value;
    if (value != 'daily') arenaPeriod = value;
    load();
  });
  Future<void> refresh() async {
    setState(load);
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final unit = type == 'all_time' ? 'rating' : 'pts';
    return Scaffold(
      appBar: ArenaBar(
        title: const Text('Top performers'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 800,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: FutureBuilder(
            future: future,
            builder: (context, snapshot) {
              final waiting = snapshot.connectionState != ConnectionState.done;
              final board = waiting || snapshot.hasError
                  ? cached
                  : snapshot.data;
              final rows = (board?['rows'] as List? ?? [])
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList();
              final mine = rows
                  .where((r) => r['id'] == session.profile!.id)
                  .firstOrNull;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: context.tokens.raised,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _BoardTab(
                              label: 'Battle arena',
                              icon: Icons.sports_esports_outlined,
                              selected: type != 'daily',
                              onTap: () => select(arenaPeriod),
                            ),
                          ),
                          Expanded(
                            child: _BoardTab(
                              label: 'Daily quiz',
                              icon: Icons.public_rounded,
                              selected: type == 'daily',
                              onTap: () => select('daily'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (type != 'daily')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('This week'),
                          selected: type == 'weekly',
                          onSelected: (_) => select('weekly'),
                        ),
                        ChoiceChip(
                          label: const Text('All-time rating'),
                          selected: type == 'all_time',
                          onSelected: (_) => select('all_time'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    type == 'daily'
                        ? 'Today’s shared challenge · resets at midnight IST'
                        : type == 'weekly'
                        ? 'Battle points earned this week · resets Monday IST'
                        : 'Your overall battle rating, across every season',
                    style: context.type.bodySmall,
                  ),
                  if (session.preview)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Sample rankings · local preview',
                        style: context.type.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (waiting && board == null)
                    const ArenaSkeleton(
                      layout: SkeletonLayout.standings,
                      label: 'Updating the standings…',
                    )
                  else if (snapshot.hasError && board == null)
                    EmptyState(
                      title: 'Rankings couldn’t load',
                      message:
                          'Reconnect and try again. Your progress is saved.',
                      action: OutlinedButton(
                        onPressed: refresh,
                        child: const Text('Retry'),
                      ),
                    )
                  else ...[
                    if (waiting)
                      Text(
                        'Refreshing standings…',
                        style: context.type.bodySmall,
                      ),
                    if (snapshot.hasError)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Showing saved standings'),
                        trailing: TextButton(
                          onPressed: refresh,
                          child: const Text('Retry'),
                        ),
                      ),
                    Text(
                      'Your standing',
                      style: context.type.titleSmall?.copyWith(
                        color: context.tokens.secondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Standing(
                      entry: mine,
                      name: session.profile!.fullName,
                      unit: unit,
                    ),
                    if (rows.isEmpty) ...[
                      const SizedBox(height: 24),
                      EmptyState(
                        title: 'The podium is waiting',
                        message: type == 'daily'
                            ? 'Complete today’s challenge to join the standings.'
                            : 'Play a battle to start climbing the rankings.',
                        icon: Icons.emoji_events_outlined,
                        action: OutlinedButton(
                          onPressed: () => context.push(
                            type == 'daily' ? '/daily' : '/matchmaking',
                          ),
                          child: Text(
                            type == 'daily'
                                ? 'Take the challenge'
                                : 'Play a battle',
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 28),
                      Arrive(
                        key: ValueKey(type),
                        from: const Offset(0, 16),
                        child: ArenaCard(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                type == 'daily'
                                    ? 'Daily podium'
                                    : type == 'weekly'
                                    ? 'Weekly podium'
                                    : 'All-time podium',
                                style: context.type.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              _Podium(
                                entries: rows.take(3).toList(),
                                unit: unit,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SectionHeading(
                        title: 'Top rankings',
                        action: '${rows.length} learners',
                      ),
                      const SizedBox(height: 12),
                      for (final entry in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RankingRow(
                            entry: entry,
                            you: entry['id'] == session.profile!.id,
                            unit: unit,
                          ),
                        ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected ? context.tokens.card : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : context.tokens.muted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.type.titleSmall?.copyWith(
                    color: selected ? context.tokens.ink : context.tokens.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Standing extends StatelessWidget {
  const _Standing({
    required this.entry,
    required this.name,
    required this.unit,
  });
  final Map<String, dynamic>? entry;
  final String name, unit;
  @override
  Widget build(BuildContext context) => ArenaPanel(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: arenaMint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            entry == null ? '—' : '#${entry!['rank']}',
            style: context.type.titleSmall?.copyWith(color: arenaInk),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: context.type.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ArenaTokens.teal,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'You',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry == null
                    ? 'Complete a round to get ranked'
                    : entry!['rating'] == null
                    ? 'Battle arena'
                    : '${RankTier.forRating((entry!["rating"] as num).toInt()).label} tier',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        if (entry != null) ...[
          const SizedBox(width: 8),
          Column(
            children: [
              CountMetric(
                (entry!['metric'] as num).toInt(),
                format: NumberFormat.compact().format,
                style: context.type.titleLarge?.copyWith(color: arenaMint),
              ),
              Text(unit, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.unit});
  final List<Map<String, dynamic>> entries;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final order = entries.length >= 2 ? [1, 0, if (entries.length > 2) 2] : [0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final index in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RankMedal(
                    rank: (entries[index]['rank'] as num).toInt(),
                    size: entries[index]['rank'] == 1 ? 46 : 38,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(12) * 3,
                    child: Center(
                      child: Text(
                        entries[index]['full_name'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.type.titleSmall?.copyWith(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height:
                        (entries[index]['rank'] == 1
                            ? 122.0
                            : entries[index]['rank'] == 2
                            ? 96.0
                            : 78.0) +
                        (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                              0,
                              3,
                            ) *
                            56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entries[index]['rank'] == 1
                          ? ArenaTokens.gold
                          : entries[index]['rank'] == 2
                          ? ArenaTokens.silver
                          : ArenaTokens.bronze,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          NumberFormat.compact().format(
                            entries[index]['metric'],
                          ),
                          maxLines: 1,
                          style: const TextStyle(
                            color: ArenaTokens.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          unit,
                          style: const TextStyle(
                            color: ArenaTokens.navy,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.entry,
    required this.you,
    required this.unit,
  });
  final Map<String, dynamic> entry;
  final bool you;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final rank = (entry['rank'] as num).toInt();
    return ArenaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: you ? ArenaTokens.teal.withValues(alpha: .06) : null,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: rank <= 3
                ? RankMedal(rank: rank, size: 36)
                : Text(
                    '#$rank',
                    style: context.type.titleSmall?.copyWith(
                      color: context.tokens.muted,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['full_name']}${you ? ' · You' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.titleSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (entry['rating'] != null)
                      RankTier.forRating(
                        (entry['rating'] as num).toInt(),
                      ).label,
                    if (entry['level'] != null) 'Level ${entry['level']}',
                  ].join(' · '),
                  style: context.type.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Points(value: entry['metric'], unit: unit),
        ],
      ),
    );
  }
}

class _Points extends StatelessWidget {
  const _Points({required this.value, required this.unit});
  final num value;
  final String unit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      CountMetric(
        value.toInt(),
        format: NumberFormat.compact().format,
        style: context.type.titleLarge,
      ),
      Text(unit, style: context.type.bodySmall),
    ],
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/data/session.dart';
import '../features/auth/domain/models.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/categories/presentation/category_screen.dart';
import '../features/practice/presentation/quiz_screen.dart';
import '../features/admin/presentation/admin_screen.dart';
import '../features/battle/presentation/battle_screen.dart';
import '../features/leaderboard/presentation/leaderboard_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/daily_challenge/presentation/daily_screen.dart';
import '../shared/gallery_screen.dart';
import '../shared/widgets.dart';
import '../features/history/presentation/review_screen.dart';
import '../features/matchmaking/presentation/matchmaking_screen.dart';
import '../features/admin/presentation/question_editor_screen.dart';
part 'router.g.dart';

@TypedGoRoute<HomeRoute>(path: '/')
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const HomeScreen();
}

@TypedGoRoute<LoginRoute>(path: '/login')
class LoginRoute extends GoRouteData with $LoginRoute {
  const LoginRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LoginScreen();
}

@TypedGoRoute<CompleteProfileRoute>(path: '/complete-profile')
class CompleteProfileRoute extends GoRouteData with $CompleteProfileRoute {
  const CompleteProfileRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CompleteProfileScreen();
}

@TypedGoRoute<CategoryRoute>(path: '/categories')
class CategoryRoute extends GoRouteData with $CategoryRoute {
  const CategoryRoute({this.mode = 'practice'});
  final String mode;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      CategoryScreen(mode: mode);
}

@TypedGoRoute<QuizRoute>(path: '/quiz')
class QuizRoute extends GoRouteData with $QuizRoute {
  const QuizRoute({
    this.category = 'mixed',
    this.subtopic,
    this.mode = 'practice',
    this.timed = true,
    this.exam,
    this.difficulty,
    this.count = 10,
  });
  final String category, mode;
  final String? subtopic, exam, difficulty;
  final int count;
  final bool timed;
  @override
  Widget build(BuildContext context, GoRouterState state) => QuizScreen(
    category: category,
    subtopic: subtopic,
    mode: mode,
    timed: timed,
    exam: exam,
    difficulty: difficulty,
    questionCount: count,
  );
}

@TypedGoRoute<ReviewRoute>(path: '/review')
class ReviewRoute extends GoRouteData with $ReviewRoute {
  const ReviewRoute({this.$extra});
  final List<Map<String, dynamic>>? $extra;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      ReviewScreen(questions: $extra ?? []);
}

@TypedGoRoute<MatchmakingRoute>(path: '/matchmaking')
class MatchmakingRoute extends GoRouteData with $MatchmakingRoute {
  const MatchmakingRoute({this.category = 'mixed', this.subtopic});
  final String category;
  final String? subtopic;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      MatchmakingScreen(category: category, subtopic: subtopic);
}

@TypedGoRoute<BattleRoute>(path: '/battle/:id')
class BattleRoute extends GoRouteData with $BattleRoute {
  const BattleRoute({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BattleScreen(matchId: id);
}

@TypedGoRoute<DailyRoute>(path: '/daily')
class DailyRoute extends GoRouteData with $DailyRoute {
  const DailyRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DailyScreen();
}

@TypedGoRoute<LeaderboardRoute>(path: '/leaderboard')
class LeaderboardRoute extends GoRouteData with $LeaderboardRoute {
  const LeaderboardRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LeaderboardScreen();
}

@TypedGoRoute<HistoryRoute>(path: '/history')
class HistoryRoute extends GoRouteData with $HistoryRoute {
  const HistoryRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const HistoryScreen();
}

@TypedGoRoute<ProfileRoute>(path: '/profile')
class ProfileRoute extends GoRouteData with $ProfileRoute {
  const ProfileRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const ProfileScreen();
}

@TypedGoRoute<SettingsRoute>(path: '/settings')
class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SettingsScreen();
}

@TypedGoRoute<EditProfileRoute>(path: '/edit-profile')
class EditProfileRoute extends GoRouteData with $EditProfileRoute {
  const EditProfileRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CompleteProfileScreen(editing: true);
}

@TypedGoRoute<AdminRoute>(path: '/admin')
class AdminRoute extends GoRouteData with $AdminRoute {
  const AdminRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AdminScreen();
}

@TypedGoRoute<QuestionEditorRoute>(path: '/admin/question')
class QuestionEditorRoute extends GoRouteData with $QuestionEditorRoute {
  const QuestionEditorRoute({this.$extra});
  final Map<String, dynamic>? $extra;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      QuestionEditorScreen(question: $extra);
}

@TypedGoRoute<GalleryRoute>(path: '/gallery')
class GalleryRoute extends GoRouteData with $GalleryRoute {
  const GalleryRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const GalleryScreen();
}

GoRouter createRouter(SessionController session) => GoRouter(
  initialLocation: '/',
  refreshListenable: session,
  redirect: (context, state) {
    if (state.uri.path == '/gallery' && kDebugMode) return null;
    return routeRedirect(
      signedIn: session.signedIn,
      completed: session.completed,
      role: session.role,
      path: state.uri.path,
    );
  },
  errorBuilder: (context, state) => Scaffold(
    body: EmptyState(
      title: 'This page took a wrong turn',
      message: 'Head home to pick up where you left off.',
      action: TextButton(
        onPressed: () => context.go('/'),
        child: const Text('Go home'),
      ),
    ),
  ),
  routes: [
    ...$appRoutes.where(
      (r) => [
        '/login',
        '/complete-profile',
        '/quiz',
        '/review',
        '/categories',
        '/matchmaking',
        '/battle/:id',
        '/daily',
        '/settings',
        '/edit-profile',
        '/admin/question',
        '/gallery',
      ].contains((r as GoRoute).path),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          _AppShell(session: session, path: state.uri.path, child: child),
      routes: $appRoutes
          .where(
            (r) => [
              '/',
              '/leaderboard',
              '/history',
              '/profile',
              '/admin',
            ].contains((r as GoRoute).path),
          )
          .toList(),
    ),
  ],
);

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.session,
    required this.path,
    required this.child,
  });
  final SessionController session;
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final destinations = [
      ('/', Icons.home_outlined, 'Home', Icons.home_rounded),
      (
        '/leaderboard',
        Icons.emoji_events_outlined,
        'Leaderboard',
        Icons.emoji_events_rounded,
      ),
      ('/profile', Icons.insights_outlined, 'Progress', Icons.insights_rounded),
      if (session.role.isAdmin)
        (
          '/admin',
          Icons.admin_panel_settings_outlined,
          'Admin',
          Icons.admin_panel_settings_rounded,
        ),
    ];
    final index = destinations
        .indexWhere((d) => d.$1 == (path == '/history' ? '/profile' : path))
        .clamp(0, destinations.length - 1);
    final content = Column(
      children: [
        if (session.preview)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'Local preview · sample data · no live rating changes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Scaffold(
        body: constraints.maxWidth >= 1000
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    extended: true,
                    minExtendedWidth: 240,
                    labelType: NavigationRailLabelType.none,
                    onDestinationSelected: (i) =>
                        context.go(destinations[i].$1),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.$2),
                          selectedIcon: Icon(d.$4),
                          label: Text(d.$3),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: constraints.maxWidth >= 1000
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerTheme.color!,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: NavigationBar(
                    animationDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    selectedIndex: index,
                    onDestinationSelected: (i) =>
                        context.go(destinations[i].$1),
                    destinations: [
                      for (final d in destinations)
                        NavigationDestination(
                          icon: Icon(d.$2),
                          selectedIcon: Icon(d.$4),
                          label: d.$3,
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

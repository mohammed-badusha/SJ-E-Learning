// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [
  $homeRoute,
  $loginRoute,
  $completeProfileRoute,
  $categoryRoute,
  $quizRoute,
  $reviewRoute,
  $matchmakingRoute,
  $battleRoute,
  $dailyRoute,
  $leaderboardRoute,
  $historyRoute,
  $profileRoute,
  $settingsRoute,
  $editProfileRoute,
  $adminRoute,
  $questionEditorRoute,
  $galleryRoute,
];

RouteBase get $homeRoute =>
    GoRouteData.$route(path: '/', factory: $HomeRoute._fromState);

mixin $HomeRoute on GoRouteData {
  static HomeRoute _fromState(GoRouterState state) => const HomeRoute();

  @override
  String get location => GoRouteData.$location('/');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $loginRoute =>
    GoRouteData.$route(path: '/login', factory: $LoginRoute._fromState);

mixin $LoginRoute on GoRouteData {
  static LoginRoute _fromState(GoRouterState state) => const LoginRoute();

  @override
  String get location => GoRouteData.$location('/login');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $completeProfileRoute => GoRouteData.$route(
  path: '/complete-profile',
  factory: $CompleteProfileRoute._fromState,
);

mixin $CompleteProfileRoute on GoRouteData {
  static CompleteProfileRoute _fromState(GoRouterState state) =>
      const CompleteProfileRoute();

  @override
  String get location => GoRouteData.$location('/complete-profile');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $categoryRoute =>
    GoRouteData.$route(path: '/categories', factory: $CategoryRoute._fromState);

mixin $CategoryRoute on GoRouteData {
  static CategoryRoute _fromState(GoRouterState state) =>
      CategoryRoute(mode: state.uri.queryParameters['mode'] ?? 'practice');

  CategoryRoute get _self => this as CategoryRoute;

  @override
  String get location => GoRouteData.$location(
    '/categories',
    queryParams: {if (_self.mode != 'practice') 'mode': _self.mode},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $quizRoute =>
    GoRouteData.$route(path: '/quiz', factory: $QuizRoute._fromState);

mixin $QuizRoute on GoRouteData {
  static QuizRoute _fromState(GoRouterState state) => QuizRoute(
    category: state.uri.queryParameters['category'] ?? 'mixed',
    subtopic: state.uri.queryParameters['subtopic'],
    mode: state.uri.queryParameters['mode'] ?? 'practice',
    timed:
        _$convertMapValue(
          'timed',
          state.uri.queryParameters,
          _$boolConverter,
        ) ??
        true,
    exam: state.uri.queryParameters['exam'],
    difficulty: state.uri.queryParameters['difficulty'],
    count:
        _$convertMapValue('count', state.uri.queryParameters, int.parse) ?? 10,
  );

  QuizRoute get _self => this as QuizRoute;

  @override
  String get location => GoRouteData.$location(
    '/quiz',
    queryParams: {
      if (_self.category != 'mixed') 'category': _self.category,
      if (_self.subtopic != null) 'subtopic': _self.subtopic,
      if (_self.mode != 'practice') 'mode': _self.mode,
      if (_self.timed != true) 'timed': _self.timed.toString(),
      if (_self.exam != null) 'exam': _self.exam,
      if (_self.difficulty != null) 'difficulty': _self.difficulty,
      if (_self.count != 10) 'count': _self.count.toString(),
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

T? _$convertMapValue<T>(
  String key,
  Map<String, String> map,
  T? Function(String) converter,
) {
  final value = map[key];
  return value == null ? null : converter(value);
}

bool _$boolConverter(String value) {
  switch (value) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      throw UnsupportedError('Cannot convert "$value" into a bool.');
  }
}

RouteBase get $reviewRoute =>
    GoRouteData.$route(path: '/review', factory: $ReviewRoute._fromState);

mixin $ReviewRoute on GoRouteData {
  static ReviewRoute _fromState(GoRouterState state) =>
      ReviewRoute($extra: state.extra as List<Map<String, dynamic>>?);

  ReviewRoute get _self => this as ReviewRoute;

  @override
  String get location => GoRouteData.$location('/review');

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $matchmakingRoute => GoRouteData.$route(
  path: '/matchmaking',
  factory: $MatchmakingRoute._fromState,
);

mixin $MatchmakingRoute on GoRouteData {
  static MatchmakingRoute _fromState(GoRouterState state) => MatchmakingRoute(
    category: state.uri.queryParameters['category'] ?? 'mixed',
    subtopic: state.uri.queryParameters['subtopic'],
  );

  MatchmakingRoute get _self => this as MatchmakingRoute;

  @override
  String get location => GoRouteData.$location(
    '/matchmaking',
    queryParams: {
      if (_self.category != 'mixed') 'category': _self.category,
      if (_self.subtopic != null) 'subtopic': _self.subtopic,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $battleRoute =>
    GoRouteData.$route(path: '/battle/:id', factory: $BattleRoute._fromState);

mixin $BattleRoute on GoRouteData {
  static BattleRoute _fromState(GoRouterState state) =>
      BattleRoute(id: state.pathParameters['id']!);

  BattleRoute get _self => this as BattleRoute;

  @override
  String get location =>
      GoRouteData.$location('/battle/${Uri.encodeComponent(_self.id)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $dailyRoute =>
    GoRouteData.$route(path: '/daily', factory: $DailyRoute._fromState);

mixin $DailyRoute on GoRouteData {
  static DailyRoute _fromState(GoRouterState state) => const DailyRoute();

  @override
  String get location => GoRouteData.$location('/daily');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $leaderboardRoute => GoRouteData.$route(
  path: '/leaderboard',
  factory: $LeaderboardRoute._fromState,
);

mixin $LeaderboardRoute on GoRouteData {
  static LeaderboardRoute _fromState(GoRouterState state) =>
      const LeaderboardRoute();

  @override
  String get location => GoRouteData.$location('/leaderboard');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $historyRoute =>
    GoRouteData.$route(path: '/history', factory: $HistoryRoute._fromState);

mixin $HistoryRoute on GoRouteData {
  static HistoryRoute _fromState(GoRouterState state) => const HistoryRoute();

  @override
  String get location => GoRouteData.$location('/history');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $profileRoute =>
    GoRouteData.$route(path: '/profile', factory: $ProfileRoute._fromState);

mixin $ProfileRoute on GoRouteData {
  static ProfileRoute _fromState(GoRouterState state) => const ProfileRoute();

  @override
  String get location => GoRouteData.$location('/profile');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $settingsRoute =>
    GoRouteData.$route(path: '/settings', factory: $SettingsRoute._fromState);

mixin $SettingsRoute on GoRouteData {
  static SettingsRoute _fromState(GoRouterState state) => const SettingsRoute();

  @override
  String get location => GoRouteData.$location('/settings');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $editProfileRoute => GoRouteData.$route(
  path: '/edit-profile',
  factory: $EditProfileRoute._fromState,
);

mixin $EditProfileRoute on GoRouteData {
  static EditProfileRoute _fromState(GoRouterState state) =>
      const EditProfileRoute();

  @override
  String get location => GoRouteData.$location('/edit-profile');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $adminRoute =>
    GoRouteData.$route(path: '/admin', factory: $AdminRoute._fromState);

mixin $AdminRoute on GoRouteData {
  static AdminRoute _fromState(GoRouterState state) => const AdminRoute();

  @override
  String get location => GoRouteData.$location('/admin');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $questionEditorRoute => GoRouteData.$route(
  path: '/admin/question',
  factory: $QuestionEditorRoute._fromState,
);

mixin $QuestionEditorRoute on GoRouteData {
  static QuestionEditorRoute _fromState(GoRouterState state) =>
      QuestionEditorRoute($extra: state.extra as Map<String, dynamic>?);

  QuestionEditorRoute get _self => this as QuestionEditorRoute;

  @override
  String get location => GoRouteData.$location('/admin/question');

  @override
  void go(BuildContext context) => context.go(location, extra: _self.$extra);

  @override
  Future<T?> push<T>(BuildContext context) =>
      context.push<T>(location, extra: _self.$extra);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location, extra: _self.$extra);

  @override
  void replace(BuildContext context) =>
      context.replace(location, extra: _self.$extra);
}

RouteBase get $galleryRoute =>
    GoRouteData.$route(path: '/gallery', factory: $GalleryRoute._fromState);

mixin $GalleryRoute on GoRouteData {
  static GalleryRoute _fromState(GoRouterState state) => const GalleryRoute();

  @override
  String get location => GoRouteData.$location('/gallery');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

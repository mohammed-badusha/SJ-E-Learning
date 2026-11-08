import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/audio/audio_controller.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/auth/data/session.dart';
import 'shared/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('preferences');
  await Hive.openBox<dynamic>('review');
  if (Env.configured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseKey,
    );
  }
  runApp(const ProviderScope(child: SJLearningApp()));
}

class SJLearningApp extends ConsumerStatefulWidget {
  const SJLearningApp({super.key});
  @override
  ConsumerState<SJLearningApp> createState() => _AppState();
}

class _AppState extends ConsumerState<SJLearningApp> {
  late final SessionController session;
  late final GoRouter router;
  @override
  void initState() {
    super.initState();
    session = ref.read(sessionProvider);
    ref.read(audioProvider);
    router = createRouter(session);
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MaterialApp.router(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      theme: arenaTheme(Brightness.light),
      darkTheme: arenaTheme(Brightness.dark),
      themeMode: session.themeMode,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: session.loading
              ? const Scaffold(body: Center(child: SJMark(size: 72)))
              : child!,
        );
      },
    ),
  );
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/env.dart';
import '../domain/models.dart';
part 'session.g.dart';

@Riverpod(keepAlive: true)
SessionController session(Ref ref) {
  final controller = SessionController(
    Env.configured ? Supabase.instance.client : null,
  );
  ref.onDispose(controller.dispose);
  return controller;
}

class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController(this.client) {
    WidgetsBinding.instance.addObserver(this);
    if (Hive.isBoxOpen('preferences')) {
      final prefs = Hive.box<dynamic>('preferences');
      if (prefs.get('light_design_v1', defaultValue: false) != true) {
        prefs.put('theme', ThemeMode.light.index);
        prefs.put('light_design_v1', true);
      }
      final index =
          (prefs.get('theme', defaultValue: ThemeMode.light.index) as int)
              .clamp(0, 2);
      themeMode = ThemeMode.values[index];
      haptics = prefs.get('haptics', defaultValue: true) as bool;
    }
    _subscription = client?.auth.onAuthStateChange.listen(
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }
  final SupabaseClient? client;
  StreamSubscription<AuthState>? _subscription;
  Profile? profile;
  AdminRole role = AdminRole.student;
  bool preview = false;
  bool loading = true;
  String? error;
  bool _disposed = false;
  bool _googleInitialized = false;
  bool get signedIn => preview || client?.auth.currentSession != null;
  bool get completed =>
      profile?.profileCompleted == true && profile?.isBanned != true;
  ThemeMode themeMode = ThemeMode.light;
  bool haptics = true;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (preview) return;
    if (client?.auth.currentSession == null) {
      profile = null;
      role = AdminRole.student;
      loading = false;
      _notify();
      return;
    }
    try {
      final data = await client!
          .from('profiles')
          .select(
            'id,full_name,phone,avatar_url,profile_completed,rating,xp,level,current_streak,best_streak,target_exam,is_banned',
          )
          .eq('id', client!.auth.currentUser!.id)
          .maybeSingle();
      final nextRole = await client!.rpc('get_my_role');
      profile = data == null ? null : Profile.fromJson(data);
      role = AdminRole.parse(nextRole as String);
      error = profile?.isBanned == true
          ? 'This account is suspended. Please contact the academy.'
          : null;
    } catch (_) {
      // Fail closed: a stale cached role never grants administrator access.
      role = AdminRole.student;
      profile = null;
      error = 'We couldn’t load your profile. Check your connection and retry.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> signIn() async {
    if (client == null) {
      throw StateError(
        'Connect your Supabase project first. See docs/SETUP.md.',
      );
    }
    if (kIsWeb) {
      await client!.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
      );
      return;
    }
    if (Env.googleWebClientId.isEmpty) {
      throw StateError('Google OAuth client ID hasn’t been configured yet.');
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(
        clientId: Env.googleIosClientId.isEmpty ? null : Env.googleIosClientId,
        serverClientId: Env.googleWebClientId,
      );
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError(
        'Google did not return an ID token. Check OAuth configuration.',
      );
    }
    await client!.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    await refresh();
  }

  void enterPreview() {
    preview = true;
    role = AdminRole.student;
    loading = false;
    error = null;
    profile = const Profile(
      id: 'preview',
      fullName: 'Alex Learner',
      profileCompleted: true,
      rating: 1240,
      xp: 180,
      level: 3,
      currentStreak: 7,
      bestStreak: 12,
      targetExam: 'SSC',
    );
    _notify();
  }

  Future<void> completeProfile(String name, String phone) async {
    if (validateName(name) != null || validatePhone(phone) != null) {
      throw ArgumentError('Check your name and phone.');
    }
    await client!.rpc(
      'complete_profile',
      params: {
        'full_name': name.trim(),
        'phone': '+91${normalizePhone(phone)}',
      },
    );
    await refresh();
    if (!completed) {
      throw StateError(error ?? 'Profile could not be saved. Please retry.');
    }
  }

  void setTheme(ThemeMode value) {
    themeMode = value;
    if (Hive.isBoxOpen('preferences')) {
      Hive.box<dynamic>('preferences').put('theme', value.index);
    }
    _notify();
  }

  void setHaptics(bool value) {
    haptics = value;
    if (Hive.isBoxOpen('preferences')) {
      Hive.box<dynamic>('preferences').put('haptics', value);
    }
    _notify();
  }

  Future<void> signOut() async {
    if (!preview) await client?.auth.signOut();
    preview = false;
    profile = null;
    role = AdminRole.student;
    error = null;
    if (Hive.isBoxOpen('review')) await Hive.box<dynamic>('review').clear();
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

    _subscription = client?.auth.onAuthStateChange.listen(
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }
  final SupabaseClient? client;
  StreamSubscription<AuthState>? _subscription;
  final dataChanges = ValueNotifier<int>(0);
  Map<String, dynamic> preferences = {};
  final List<RealtimeChannel> _dataChannels = [];
  String? _subscribedUser;
  Timer? _dataDebounce;
  bool _refreshing = false;
  Future<void> savePreferences(Map<String, dynamic> patch) async {
    if (preview || client?.auth.currentUser == null) return;
    try {
      preferences = Map<String, dynamic>.from(
        await client!.rpc('save_preferences', params: {'patch': patch}),
      );
      error = null;
    } catch (_) {
      error = 'Settings could not be saved. Reconnect and try again.';
    }
    _notify();
  }

  void _subscribeData() {
    final uid = client?.auth.currentUser?.id;
    if ('$uid:${role.name}' == _subscribedUser) return;
    for (final channel in _dataChannels) {
      unawaited(client!.removeChannel(channel));
    }
    _dataChannels.clear();
    _subscribedUser = '$uid:${role.name}';
    if (uid == null) preferences = {};
    if (uid == null) return;
    for (final topic in [
      'data:catalog',
      'data:user:$uid',
      if (role.isAdmin) 'data:admin',
    ]) {
      final channel = client!.channel(
        topic,
        opts: const RealtimeChannelConfig(private: true),
      );
      void changed(Map<String, dynamic> _) {
        _dataDebounce?.cancel();
        _dataDebounce = Timer(const Duration(milliseconds: 250), () {
          if (_disposed) return;
          dataChanges.value++;
          if (topic.startsWith('data:user:')) unawaited(refresh());
        });
      }

      channel
          .onBroadcast(event: 'changed', callback: changed)
          .onBroadcast(event: 'standings', callback: changed)
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed && !_disposed) {
              dataChanges.value++;
            }
          });
      _dataChannels.add(channel);
    }
  }

  Profile? profile;
  AdminRole role = AdminRole.student;
  bool preview = false;
  bool loading = true;
  String? error;
  bool _disposed = false;
  bool get signedIn => preview || client?.auth.currentSession != null;
  bool get completed =>
      profile?.profileCompleted == true && profile?.isBanned != true;
  ThemeMode themeMode = ThemeMode.light;
  bool haptics = true;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (preview || _refreshing) return;
    _subscribeData();
    if (client?.auth.currentSession == null) {
      profile = null;
      role = AdminRole.student;
      loading = false;
      _notify();
      return;
    }
    _refreshing = true;
    try {
      final pref = await client!
          .from('user_preferences')
          .select('settings')
          .eq('user_id', client!.auth.currentUser!.id)
          .maybeSingle();
      preferences = Map<String, dynamic>.from(pref?['settings'] ?? {});
      themeMode =
          ThemeMode.values[(preferences['theme'] as int? ?? 1).clamp(0, 2)];
      haptics = preferences['haptics'] as bool? ?? true;
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
      _subscribeData();
      error = profile?.isBanned == true
          ? 'This account is suspended. Please contact the academy.'
          : null;
    } catch (_) {
      // Fail closed: a stale cached role never grants administrator access.
      role = AdminRole.student;
      profile = null;
      error = 'We couldn’t load your profile. Check your connection and retry.';
    } finally {
      _refreshing = false;
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
    await client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.redirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
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

  Future<void> completeProfile(
    String name,
    String phone, {
    String? portrait,
    Uint8List? photo,
  }) async {
    if (validateName(name) != null || validatePhone(phone) != null) {
      throw ArgumentError('Check your name and phone.');
    }
    await client!.rpc(
      portrait == null ? 'complete_profile' : 'save_profile_portrait',
      params: {
        'full_name': name.trim(),
        if (portrait != null) 'portrait': portrait,
        if (photo != null) 'photo_png': base64Encode(photo),
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
    unawaited(savePreferences({'theme': value.index}));

    _notify();
  }

  void setHaptics(bool value) {
    haptics = value;
    unawaited(savePreferences({'haptics': value}));

    _notify();
  }

  Future<void> signOut() async {
    if (!preview) await client?.auth.signOut();
    preview = false;
    profile = null;
    role = AdminRole.student;
    error = null;

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
    _dataDebounce?.cancel();
    for (final channel in _dataChannels) {
      unawaited(client!.removeChannel(channel));
    }
    dataChanges.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

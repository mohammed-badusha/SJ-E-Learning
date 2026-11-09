import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/env.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/arena_motion.dart';
import 'portrait_picker.dart';
import '../data/session.dart';
import '../domain/models.dart';
import 'sign_in_error.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  bool busy = false;
  String? error;
  Future<void> signIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(sessionProvider).signIn();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SJ_AUTH_FAILURE ${signInDiagnosticCode(error)}');
      }
      if (mounted) {
        setState(
          () => this.error = signInErrorMessage(
            error,
            configured: Env.configured,
            includeDiagnosticCode: kDebugMode,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF10192B) : Colors.white,
        body: Stack(
          children: [
            // Background image — transparent, clipped to hide red corners
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  maxWidth: MediaQuery.sizeOf(context).width * 1.15,
                  maxHeight: screenHeight * 1.15,
                  child: Opacity(
                    opacity: isDark ? 0.18 : 0.22,
                    child: Image.asset(
                      'assets/images/image.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.08),

                          // SJ Logo — kept unchanged
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : const Color(0xFFF5F7FB),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFFE2E7F0),
                              ),
                            ),
                            child: const SJMark(size: 48),
                          ),
                          const SizedBox(height: 16),

                          // App name — kept unchanged
                          Text(
                            'SJ E-Learning',
                            style: context.type.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Tagline label
                          Text(
                            'YOUR SUCCESS STARTS HERE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                              color: context.tokens.muted,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Headline
                          Arrive(
                            child: Text(
                              'Prepare. Practice.\nSucceed.',
                              textAlign: TextAlign.center,
                              style: context.type.headlineLarge?.copyWith(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A237E),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Subtitle
                          Text(
                            'Your SSC GD preparation journey\nstarts with one step.',
                            textAlign: TextAlign.center,
                            style: context.type.bodyMedium?.copyWith(
                              color: context.tokens.secondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 36),

                          // Google Sign In Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isDark
                                    ? const Color(0xFF23324C)
                                    : Colors.white,
                                foregroundColor: isDark
                                    ? Colors.white
                                    : const Color(0xFF1f1f1f),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF354664)
                                      : const Color(0xFFE0E0E0),
                                ),
                                shape: const StadiumBorder(),
                                minimumSize: const Size(48, 54),
                                elevation: 0,
                              ),
                              onPressed: busy ? null : signIn,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/brand/google-g.png',
                                    width: 20,
                                    height: 20,
                                    excludeFromSemantics: true,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    busy
                                        ? 'Signing in\u2026'
                                        : 'Continue with Google',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Helper text
                          Text(
                            'Secure and quick sign-in with your Google account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.tokens.muted,
                            ),
                          ),

                          // Error message
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          SizedBox(height: screenHeight * 0.06),

                          // Divider line
                          Divider(color: context.tokens.line),
                          const SizedBox(height: 16),

                          // Trust badges
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 15,
                                color: context.tokens.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Secure Login',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.tokens.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '\u00b7',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.tokens.muted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.bolt_outlined,
                                size: 15,
                                color: context.tokens.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Quick Access',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.tokens.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Footer
                          Text(
                            'By continuing, you agree to our Terms & Privacy Policy.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.tokens.muted,
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key, this.editing = false});
  final bool editing;
  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends ConsumerState<CompleteProfileScreen> {
  final name = TextEditingController();
  PortraitChoice? portrait;
  final phone = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    name.text =
        session.profile?.fullName ??
        session.client?.auth.currentUser?.userMetadata?['full_name']
            as String? ??
        '';
    phone.text = normalizePhone(session.profile?.phone ?? '');
    name.addListener(update);
    phone.addListener(update);
  }

  void update() => setState(() {});
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(sessionProvider)
          .completeProfile(
            name.text,
            phone.text,
            portrait: portrait?.reference,
            photo: portrait?.photo,
          );
      if (mounted) {
        if (widget.editing && context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().contains('PHONE_IN_USE')
              ? 'That phone number is already linked to another account.'
              : 'We couldn\u2019t save your profile. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return PopScope(
      canPop: widget.editing && !busy,
      child: Scaffold(
        appBar: widget.editing
            ? ArenaBar(title: const Text('Edit profile'))
            : null,
        body: PageBody(
          maxWidth: 520,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                const SJMark(size: 56),
                const SizedBox(height: 36),
                Text(
                  widget.editing
                      ? 'Your player profile'
                      : 'Complete your profile',
                  style: context.type.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.editing
                      ? 'Update your picture, name or mobile number.'
                      : 'Choose how you\u2019ll appear in the arena.',
                  style: TextStyle(color: context.tokens.muted, fontSize: 16),
                ),
                const SizedBox(height: 32),
                IgnorePointer(
                  ignoring: busy,
                  child: PortraitPicker(
                    name: name.text,
                    original: session.profile?.avatarUrl,
                    choice: portrait,
                    onChanged: (p) => setState(() => portrait = p),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    errorText: name.text.isEmpty
                        ? null
                        : validateName(name.text),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Mobile number',
                    prefixText: '+91  ',
                    errorText: phone.text.isEmpty
                        ? null
                        : validatePhone(phone.text),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The academy uses this number to contact you. Phone numbers aren\u2019t OTP-verified.',
                  style: TextStyle(color: context.tokens.muted, fontSize: 12),
                ),
                if (session.error != null) ...[
                  const SizedBox(height: 16),
                  Text(session.error!),
                  TextButton(
                    onPressed: session.refresh,
                    child: const Text('Retry connection'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                PrimaryButton(
                  label: widget.editing ? 'Save changes' : 'Save & continue',
                  busy: busy,
                  onPressed:
                      validateName(name.text) == null &&
                          validatePhone(phone.text) == null &&
                          session.error == null
                      ? save
                      : null,
                ),
                const SizedBox(height: 12),
                if (!widget.editing)
                  Center(
                    child: TextButton(
                      onPressed: busy ? null : session.signOut,
                      child: const Text('Sign out'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

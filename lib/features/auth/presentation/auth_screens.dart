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
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: context.tokens.card,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff3329a5),
                    Color(0xff5d49d6),
                    Color(0xff8777e4),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * .075).clamp(
                        20,
                        76,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const SJMark(size: 44),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'SJ E-Learning',
                      style: context.type.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Competitive exam practice',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * .07).clamp(
                        20,
                        64,
                      ),
                    ),
                    Container(
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: const BoxDecoration(
                        color: Color(0x44ffffff),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                    ),
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: context.tokens.card,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
                    child: Arrive(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome to the arena',
                            style: context.type.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Practise a subject, challenge a rival, or see how far you’ve come.',
                            style: context.type.bodyLarge?.copyWith(
                              color: context.tokens.secondary,
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xff1f1f1f),
                                side: const BorderSide(
                                  color: Color(0xff747775),
                                ),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: busy ? null : signIn,
                              icon: Image.asset(
                                'assets/brand/google-g.png',
                                width: 20,
                                height: 20,
                                excludeFromSemantics: true,
                              ),
                              label: Text(
                                busy ? 'Signing in…' : 'Continue with Google',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            'New here? Your first sign-in creates your player profile.',
                            style: context.type.bodySmall,
                          ),
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
    ),
  );
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
              : 'We couldn’t save your profile. Check your connection and retry.',
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
                      : 'Choose how you’ll appear in the arena.',
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
                  'The academy uses this number to contact you. Phone numbers aren’t OTP-verified.',
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

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/env.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
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
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      maxWidth: 520,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            const Row(
              children: [
                SJMark(size: 44),
                SizedBox(width: 12),
                Text(
                  'SJ E-Learning',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const _ArenaIllustration(),
            const SizedBox(height: 32),
            Text(
              'Prepare for your\nnext exam',
              style: context.type.headlineLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Practise by subject, play timed quiz battles and build a daily challenge streak',
              style: context.type.bodyLarge?.copyWith(
                color: context.tokens.muted,
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Continue with Google',
              icon: Icons.login_rounded,
              busy: busy,
              onPressed: signIn,
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  ref.read(sessionProvider).enterPreview();
                  context.go('/');
                },
                child: const Text('Explore the local preview'),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Google sign-in only. Your phone number is requested after sign-in for academy communication.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.tokens.muted),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

class _ArenaIllustration extends StatelessWidget {
  const _ArenaIllustration();
  @override
  Widget build(BuildContext context) => ArenaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Multiple-choice practice',
                style: context.type.bodySmall,
              ),
            ),
            Text('A–D', style: context.type.bodySmall),
          ],
        ),
        const SizedBox(height: 16),
        Text('What is 25% of 200?', style: context.type.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final entry in [
              ('A', '25'),
              ('B', '50'),
              ('C', '75'),
              ('D', '100'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: context.tokens.raised,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Text(entry.$1, style: context.type.bodySmall),
                        const SizedBox(height: 4),
                        Text(entry.$2, style: context.type.titleMedium),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends ConsumerState<CompleteProfileScreen> {
  final name = TextEditingController();
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
      await ref.read(sessionProvider).completeProfile(name.text, phone.text);
      if (mounted) context.go('/');
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
      canPop: false,
      child: Scaffold(
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
                  'Complete your profile',
                  style: context.type.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Add your name and mobile number to continue',
                  style: TextStyle(color: context.tokens.muted, fontSize: 16),
                ),
                const SizedBox(height: 32),
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
                  label: 'Save & continue',
                  busy: busy,
                  onPressed:
                      validateName(name.text) == null &&
                          validatePhone(phone.text) == null &&
                          session.error == null
                      ? save
                      : null,
                ),
                const SizedBox(height: 12),
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

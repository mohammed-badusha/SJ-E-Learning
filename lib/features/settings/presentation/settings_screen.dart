import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/audio_controls.dart';
import '../../auth/data/session.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Appearance', style: context.type.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<ThemeMode>(
              initialValue: session.themeMode,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Follow system'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (v) {
                if (v != null) session.setTheme(v);
              },
            ),
            const SizedBox(height: 24),
            const AudioSettings(),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Haptic feedback'),
              subtitle: const Text('Feedback when you select an answer'),
              value: session.haptics,
              onChanged: session.setHaptics,
            ),
            const Divider(height: 40),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Name & mobile number'),
              subtitle: Text(
                session.preview
                    ? 'Available after Google sign-in'
                    : session.profile?.phone ?? 'Complete your profile',
              ),
              onTap: session.preview
                  ? null
                  : () => context.push('/edit-profile'),
            ),
            if (session.role.isAdmin)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.admin_panel_settings_rounded),
                title: const Text('Admin panel'),
                onTap: () => context.go('/admin'),
              ),
            const SizedBox(height: 24),
            Text(
              'SJ E-Learning · 0.1.0',
              style: TextStyle(color: context.tokens.muted),
            ),
            const SizedBox(height: 8),
            Text(
              'English · India (+91)',
              style: TextStyle(color: context.tokens.muted, fontSize: 13),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: session.signOut,
              icon: const Icon(Icons.logout_rounded),
              label: Text(session.preview ? 'Exit preview' : 'Sign out'),
            ),
            if (!session.preview)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete my account'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete your account?'),
                      content: const Text(
                        'Your personal data, practice records and daily attempts will be removed. Battle history will remain anonymous. This can’t be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep my account'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete my account'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    final response = await session.client!.functions.invoke(
                      'delete_account',
                    );
                    if (response.status != 200) {
                      throw StateError('Deletion failed');
                    }
                    await session.signOut();
                  } catch (_) {
                    if (context.mounted) {
                      showMessage(
                        context,
                        'Account deletion couldn’t finish. Please retry or contact the academy.',
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

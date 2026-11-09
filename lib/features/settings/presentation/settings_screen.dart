import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/player_avatar.dart';
import '../../../shared/arena_panel.dart';
import '../../../shared/audio_controls.dart';
import '../../auth/data/session.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
        appBar: ArenaBar(title: const Text('Settings')),
        body: PageBody(
          maxWidth: 700,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(session.error!),
                ),
              ArenaPanel(
                child: Row(
                  children: [
                    ArenaPortrait(
                      accent: arenaMint,
                      child: PlayerAvatar(
                        name: session.profile?.fullName ?? 'Learner',
                        reference: session.profile?.avatarUrl,
                        size: 54,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.profile?.fullName ?? 'Player',
                            style: context.type.titleLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            session.preview
                                ? 'Preview account'
                                : session.profile?.phone ?? 'Player profile',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    if (!session.preview)
                      IconButton(
                        tooltip: 'Edit player profile',
                        color: Colors.white,
                        onPressed: () => context.push('/edit-profile'),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('Appearance', style: context.type.titleMedium),
              const SizedBox(height: 8),
              ArenaCard(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final option in [
                      (
                        ThemeMode.system,
                        'System',
                        Icons.brightness_auto_outlined,
                      ),
                      (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                    ])
                      ChoiceChip(
                        avatar: Icon(option.$3, size: 16),
                        label: Text(option.$2),
                        selected: session.themeMode == option.$1,
                        onSelected: (_) => session.setTheme(option.$1),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const ArenaCard(child: AudioSettings()),
              const SizedBox(height: 12),
              ArenaCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Haptic feedback'),
                  subtitle: const Text('Vibrate when choosing an answer'),
                  value: session.haptics,
                  onChanged: session.setHaptics,
                ),
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
      ),
    );
  }
}

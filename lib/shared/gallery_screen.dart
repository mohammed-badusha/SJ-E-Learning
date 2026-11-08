import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'widgets.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Component gallery')),
    body: !kDebugMode
        ? const SizedBox.shrink()
        : PageBody(
            maxWidth: 700,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SJMark(size: 72),
                const SizedBox(height: 24),
                Text(
                  'Made for a little progress.',
                  style: context.type.headlineLarge,
                ),
                const SizedBox(height: 24),
                for (final state in OptionState.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionTile(
                      label: 'A',
                      text: 'An answer · ${state.name}',
                      state: state,
                      onTap: () {},
                    ),
                  ),
                const SizedBox(height: 24),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TimerRing(remaining: 14, total: 15),
                    TimerRing(remaining: 7, total: 15),
                    TimerRing(remaining: 2, total: 15),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Let’s play', onPressed: () {}),
                const SizedBox(height: 12),
                const PrimaryButton(label: 'Disabled'),
                const SizedBox(height: 24),
                const ArenaCard(
                  child: Text('A quiet card, for things that matter.'),
                ),
              ],
            ),
          ),
  );
}

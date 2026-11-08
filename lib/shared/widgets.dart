import 'package:flutter/material.dart';
import '../core/theme.dart';

class SJMark extends StatelessWidget {
  const SJMark({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SJ E-Learning',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        'assets/brand/sj-logo-source.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    ),
  );
}

class ArenaCard extends StatelessWidget {
  const ArenaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.tokens.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.tokens.line),
    ),
    child: child,
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(busy ? 'Please wait…' : label)),
            const SizedBox(width: 12),
            Icon(icon, size: 18),
          ],
        ),
      ),
    ),
  );
}

enum OptionState { idle, selected, correct, wrong, disabled, timedOut }

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.text,
    this.state = OptionState.idle,
    this.onTap,
  });
  final String label, text;
  final OptionState state;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      OptionState.correct => context.tokens.success,
      OptionState.wrong => Theme.of(context).colorScheme.error,
      OptionState.selected => Theme.of(context).colorScheme.primary,
      _ => context.tokens.line,
    };
    final selected =
        state != OptionState.idle &&
        state != OptionState.disabled &&
        state != OptionState.timedOut;
    return Semantics(
      selected: selected,
      enabled: state == OptionState.idle && onTap != null,
      excludeSemantics: true,
      button: true,
      label: 'Option $label, $text, ${state.name}',
      child: Material(
        color: selected ? color.withValues(alpha: .1) : context.tokens.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: state == OptionState.idle ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: selected ? 1.5 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: .08)
                        : context.tokens.raised,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: selected ? color : context.tokens.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(text, style: context.type.bodyLarge)),
                if (state == OptionState.idle)
                  Icon(
                    Icons.radio_button_off_rounded,
                    color: context.tokens.secondary,
                    size: 20,
                  ),
                if (state == OptionState.correct)
                  Icon(Icons.check_circle_rounded, color: color),
                if (state == OptionState.wrong)
                  Icon(Icons.cancel_rounded, color: color),
                if (state == OptionState.selected)
                  Icon(Icons.lock_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TimerRing extends StatelessWidget {
  const TimerRing({super.key, required this.remaining, required this.total});
  final double remaining, total;
  @override
  Widget build(BuildContext context) {
    final fraction = (remaining / total).clamp(0.0, 1.0);
    final color = fraction <= .25
        ? Theme.of(context).colorScheme.error
        : fraction <= .5
        ? context.tokens.warning
        : Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '${remaining.ceil()} seconds remaining',
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 3,
                color: color,
                backgroundColor: context.tokens.line,
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(
              '${remaining.ceil()}',
              style: context.type.titleLarge?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    this.name = 'SJ',
    this.size = 48,
    this.color = ArenaTokens.violet,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: context.tokens.raised,
    child: Text(
      name.isEmpty
          ? 'SJ'
          : name
                .split(' ')
                .take(2)
                .map((s) => s.isEmpty ? '' : s[0])
                .join()
                .toUpperCase(),
      style: TextStyle(
        color: context.tokens.secondary,
        fontSize: size * .3,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.auto_awesome_mosaic_rounded,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: context.tokens.secondary),
          const SizedBox(height: 20),
          Text(
            title,
            style: context.type.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: context.tokens.muted),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key});
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(24),
    itemCount: 5,
    separatorBuilder: (_, index) => const SizedBox(height: 16),
    itemBuilder: (_, index) => ArenaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 16, width: 140, color: context.tokens.line),
          const SizedBox(height: 12),
          Container(
            height: 12,
            width: double.infinity,
            color: context.tokens.line,
          ),
        ],
      ),
    ),
  );
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1320});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';

const _courses = [
  ('psc-english', 'PSC English'),
  ('ssc-reasoning', 'SSC Reasoning'),
  ('ssc-maths', 'SSC Maths Foundation'),
];

class CourseCarousel extends StatefulWidget {
  const CourseCarousel({super.key});
  @override
  State<CourseCarousel> createState() => _CourseCarouselState();
}

class _CourseCarouselState extends State<CourseCarousel>
    with WidgetsBindingObserver {
  final pages = PageController(initialPage: 300);
  int index = 0;
  Timer? timer;
  bool held = false, foreground = true, visible = true, reduce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    visible =
        // Keep compatibility with the repository's pinned Flutter 3.35 SDK.
        // ignore: deprecated_member_use
        TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (held || !foreground || !visible || reduce) return;
    timer = Timer(const Duration(seconds: 5), () => move(1));
  }

  void move(int direction) {
    if (!pages.hasClients) return;
    final next = (pages.page ?? 300).round() + direction;
    if (reduce) {
      pages.jumpToPage(next);
    } else {
      pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    }
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Listener(
            onPointerDown: (_) {
              held = true;
              schedule();
            },
            onPointerUp: (_) {
              held = false;
              schedule();
            },
            onPointerCancel: (_) {
              held = false;
              schedule();
            },
            child: PageView.builder(
              controller: pages,
              onPageChanged: (page) {
                setState(() => index = page % _courses.length);
                schedule();
              },
              itemBuilder: (context, page) {
                final course = _courses[page % _courses.length];
                return Image.asset(
                  'assets/arena/${course.$1}.webp',
                  fit: BoxFit.contain,
                  semanticLabel: course.$2,
                );
              },
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Semantics(
          label: 'Banner ${index + 1} of ${_courses.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _courses.length; i++)
                AnimatedContainer(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: i == index ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

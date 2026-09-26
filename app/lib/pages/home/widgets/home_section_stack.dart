import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';

/// Home without a tab bar (v2.1, the v4 design): Today is the one screen, and Conversations, To do
/// and Apps slide in over it from the right (See All, a notification, a widget), with Today easing
/// back underneath as in iOS navigation. [selectedIndex] 0 is Today alone; 1 to 3 is that section
/// pushed. Every section stays mounted, so each keeps its scroll position, and the last one stays
/// visible while it slides back out.
class HomeSectionStack extends StatefulWidget {
  const HomeSectionStack({super.key, required this.selectedIndex, required this.pages, required this.onBack});

  /// 0 for Today, else the pushed section.
  final int selectedIndex;

  /// Today first, then the sections in order.
  final List<Widget> pages;

  /// Back to Today: the header's back button, a swipe from the leading edge, or system back.
  final VoidCallback onBack;

  /// v4 push: 0.5 s on iOS's navigation curve.
  static const Duration push = Duration(milliseconds: 500);
  static const Curve curve = Cubic(0.32, 0.72, 0, 1);

  @override
  State<HomeSectionStack> createState() => _HomeSectionStackState();
}

class _HomeSectionStackState extends State<HomeSectionStack> {
  late int _shown = widget.selectedIndex > 0 ? widget.selectedIndex : 1;

  @override
  void didUpdateWidget(HomeSectionStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex > 0) _shown = widget.selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    final pushed = widget.selectedIndex > 0;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? Duration.zero : HomeSectionStack.push;
    final sections = widget.pages.sublist(1);
    return Stack(
      children: [
        // Today recedes a little under a pushed section.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: pushed,
            child: ExcludeSemantics(
              excluding: pushed,
              child: AnimatedSlide(
                offset: pushed ? const Offset(-0.24, 0) : Offset.zero,
                duration: duration,
                curve: HomeSectionStack.curve,
                child: AnimatedOpacity(
                  opacity: pushed ? 0.5 : 1,
                  duration: duration,
                  child: widget.pages.first,
                ),
              ),
            ),
          ),
        ),
        // The section, in from the right.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !pushed,
            child: ExcludeSemantics(
              excluding: !pushed,
              child: AnimatedSlide(
                key: const Key('home_section_layer'),
                offset: pushed ? Offset.zero : const Offset(1.02, 0),
                duration: duration,
                curve: HomeSectionStack.curve,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: OmiColors.surface0,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(-12, 0)),
                    ],
                  ),
                  child: _EdgeSwipeBack(
                    onBack: widget.onBack,
                    child: IndexedStack(index: (_shown - 1).clamp(0, sections.length - 1), children: sections),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A swipe in from the leading edge goes back to Today, like iOS's back gesture.
class _EdgeSwipeBack extends StatefulWidget {
  const _EdgeSwipeBack({required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: GestureDetector(
            key: const Key('home_section_edge_swipe'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _travel = 0,
            onHorizontalDragUpdate: (details) => _travel += rtl ? -details.delta.dx : details.delta.dx,
            onHorizontalDragEnd: (details) {
              final velocity = (details.primaryVelocity ?? 0) * (rtl ? -1 : 1);
              if (_travel > 80 || velocity > 500) {
                OmiHaptics.selection();
                widget.onBack();
              }
              _travel = 0;
            },
          ),
        ),
      ],
    );
  }
}

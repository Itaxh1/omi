import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/conversation_actions.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Swipe a conversation left to delete it (v8.13 `.swp`). Dragged part way, a red Delete shows
/// under it; let go past 44 pt and it stays open at 96 pt with Delete to tap; past 55 % of the row
/// it goes: it slides off, the row closes up, and "Conversation deleted · Undo" follows. One row is
/// open at a time; a tap on an open row closes it. Screen readers get Delete as an action.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({super.key, required this.conversation, required this.child});

  final ServerConversation conversation;
  final Widget child;

  /// The row that is open now, so opening another closes it.
  static final ValueNotifier<Object?> _open = ValueNotifier<Object?>(null);

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> with TickerProviderStateMixin {
  static const double _openWidth = 96;
  static const Color _red = Color(0xFFD92D20); // omi-ux-allow: color-literal -- the mock's swipe Delete red

  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _collapse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<double>? _slideTo;
  double _dx = 0;
  bool _dragging = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _slide.addListener(() {
      final to = _slideTo;
      if (to != null) setState(() => _dx = to.value);
    });
    SwipeToDelete._open.addListener(_onOtherOpened);
  }

  @override
  void dispose() {
    SwipeToDelete._open.removeListener(_onOtherOpened);
    if (SwipeToDelete._open.value == this) SwipeToDelete._open.value = null;
    _slide.dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _onOtherOpened() {
    final open = SwipeToDelete._open.value;
    if (open != null && open != this && _dx != 0 && !_deleting) _animateTo(0);
  }

  void _animateTo(double target) {
    _slideTo =
        Tween(begin: _dx, end: target).animate(CurvedAnimation(parent: _slide, curve: const Cubic(0.2, 0.8, 0.2, 1)));
    if (OmiMotion.of(context).standard == Duration.zero) {
      setState(() => _dx = target);
      return;
    }
    _slide.forward(from: 0);
  }

  void _start(DragStartDetails _) {
    if (_deleting) return;
    _slide.stop();
    SwipeToDelete._open.value = this;
    setState(() => _dragging = true);
  }

  void _update(DragUpdateDetails d) {
    if (_deleting) return;
    setState(() => _dx = (_dx + d.delta.dx).clamp(-MediaQuery.sizeOf(context).width, 0.0));
  }

  void _end(DragEndDetails d, double width) {
    if (_deleting) return;
    setState(() => _dragging = false);
    if (_dx < -width * 0.55) {
      unawaited(_delete(width));
    } else if (_dx < -44) {
      _animateTo(-_openWidth);
    } else {
      _animateTo(0);
      if (SwipeToDelete._open.value == this) SwipeToDelete._open.value = null;
    }
  }

  Future<void> _delete(double width) async {
    if (_deleting) return;
    _deleting = true;
    OmiHaptics.medium();
    _animateTo(-width * 1.1);
    if (OmiMotion.of(context).standard != Duration.zero) await _collapse.forward();
    if (!mounted) return;
    if (SwipeToDelete._open.value == this) SwipeToDelete._open.value = null;
    unawaited(deleteConversationsWithUndo(context, [widget.conversation]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showing = _dragging || _dx != 0;
    // The row spans the page between its margins; no LayoutBuilder, so Home's fill-the-screen
    // sliver can still measure it.
    final width = MediaQuery.sizeOf(context).width - 2 * OmiSize.screenMargin;
    final row = Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.delete): () => unawaited(_delete(width)),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _start,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: (d) => _end(d, width),
        child: Stack(
          children: [
            // The red Delete under the row.
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: showing ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: GestureDetector(
                  key: ValueKey('swipe_delete_${widget.conversation.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: showing ? () => unawaited(_delete(width)) : null,
                  child: Container(
                    color: _red,
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsetsDirectional.only(end: 22),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const OmiGlyph(OmiGlyphs.trashLine, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            l10n.delete,
                            style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(_dx, 0),
              child: ColoredBox(
                color: showing ? OmiColors.surface0 : Colors.transparent,
                child: AbsorbPointer(
                  // An open row closes on a tap instead of opening the conversation.
                  absorbing: _dx != 0,
                  child: widget.child,
                ),
              ),
            ),
            if (_dx != 0 && !_dragging)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                right: -_dx,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _animateTo(0);
                    if (SwipeToDelete._open.value == this) SwipeToDelete._open.value = null;
                  },
                ),
              ),
          ],
        ),
      ),
    );
    // `.swp`: rounded 14 pt while it moves, then the row closes up (0.26 s).
    return SizeTransition(
      sizeFactor: ReverseAnimation(CurvedAnimation(parent: _collapse, curve: Curves.easeOut)),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: ReverseAnimation(_collapse),
        child: ClipRRect(borderRadius: BorderRadius.circular(showing ? 14 : 0), child: row),
      ),
    );
  }
}

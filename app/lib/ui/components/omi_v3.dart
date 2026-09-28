import 'package:flutter/material.dart';

import 'package:omi/ui/components/omi_glyph.dart';
import 'package:omi/ui/components/omi_surface.dart';
import 'package:omi/ui/omi_tokens.dart';

// The v3 controls (the Omi v8 mock): round outlined buttons, the pushed screen's header, pill
// chips, text tabs, the check ring, the popover menu, list labels and the search pill. Sizes are the
// mock's, measured at 390 × 844.

/// A 40 pt round button with a 1 pt outline (`.sh .ib`): back, more, close.
class OmiRingButton extends StatelessWidget {
  const OmiRingButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.size = 40,
    this.glyphSize = 18,
  });

  /// An [OmiGlyphs] path.
  final String glyph;

  /// The screen-reader name.
  final String label;
  final VoidCallback onPressed;
  final double size;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: OmiPressable(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          OmiHaptics.selection();
          onPressed();
        },
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: OmiColors.outline)),
          child: OmiGlyph(glyph, size: glyphSize, color: OmiColors.textPrimary),
        ),
      ),
    );
  }
}

/// The header of a pushed v3 screen (`.sh`): 12 pt under the status bar, a 40 pt back ring on the
/// left, the title centred at 17/600, an optional control on the right, 8 pt under it.
class OmiScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const OmiScreenHeader({super.key, this.title, this.trailing, this.onBack, this.backLabel});

  final String? title;

  /// A 40 pt control on the right (usually an [OmiRingButton]); the same room stays empty without
  /// one so the title stays centred.
  final Widget? trailing;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  /// The back button's screen-reader name; defaults to the platform's "Back".
  final String? backLabel;

  /// `.sh` sits 12 pt under the top of the screen (the safe area here) and is 60 pt tall.
  static const double height = 72;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final back = backLabel ?? MaterialLocalizations.of(context).backButtonTooltip;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              OmiRingButton(
                key: const Key('screen_back'),
                glyph: OmiGlyphs.back,
                label: back,
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: title == null
                    ? const SizedBox.shrink()
                    : Semantics(
                        header: true,
                        child: Text(
                          title!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              OmiType.headline.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.34, height: 1.4),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              trailing ?? const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill chip (`.chipm`): 34 pt, 1 pt outline, a 15 pt glyph and 14 pt words in the 80 % ink.
class OmiPillChip extends StatelessWidget {
  const OmiPillChip({super.key, required this.label, this.glyph, this.onTap, this.semanticHint});

  final String label;

  /// An [OmiGlyphs] path.
  final String? glyph;
  final VoidCallback? onTap;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final ink = OmiColors.ink80;
    // 34 pt at the default text size; it grows with the text rather than clipping it.
    Widget chip = Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(borderRadius: OmiRadius.pillAll, border: Border.all(color: OmiColors.outline)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[OmiGlyph(glyph!, size: 15, color: ink), const SizedBox(width: 8)],
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: OmiType.detail.copyWith(color: ink, height: 1.4)),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      hint: semanticHint,
      child: OmiPressable(onTap: onTap, child: chip),
    );
  }
}

/// One tab of [OmiTextTabs].
class OmiTextTab<T> {
  const OmiTextTab({required this.value, required this.label, this.count});

  final T value;
  final String label;

  /// A small count after the label ("To-dos 2").
  final int? count;
}

/// Text tabs over a hairline (`.ctabs`): 15/600, the selected one in ink with a 2 pt underline,
/// the others in the secondary ink, 22 pt apart.
class OmiTextTabs<T> extends StatelessWidget {
  const OmiTextTabs({super.key, required this.tabs, required this.selected, required this.onChanged});

  final List<OmiTextTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.outline))),
      child: Row(
        children: [
          for (final (i, tab) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 22),
            _tab(context, tab),
          ],
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, OmiTextTab<T> tab) {
    final on = tab.value == selected;
    final color = on ? OmiColors.textPrimary : OmiColors.textSecondary;
    return Semantics(
      button: true,
      selected: on,
      label: tab.count == null ? tab.label : '${tab.label} ${tab.count}',
      excludeSemantics: true,
      onTap: () => onChanged(tab.value),
      child: GestureDetector(
        key: ValueKey('tab_${tab.value}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (on) return;
          OmiHaptics.selection();
          onChanged(tab.value);
        },
        child: Transform.translate(
          // The underline sits on the hairline (`margin-bottom: -1px`).
          offset: const Offset(0, 1),
          child: Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? OmiColors.textPrimary : Colors.transparent, width: 2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tab.label,
                    style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600, color: color, height: 1.4)),
                if (tab.count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    height: 18,
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: OmiColors.divider, borderRadius: OmiRadius.pillAll),
                    child: Text('${tab.count}',
                        style: OmiType.caption1
                            .copyWith(fontWeight: FontWeight.w600, color: OmiColors.ink80, height: 1.2)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The to-do check (`.cb`): a 20 pt ring in ink; ticked, it fills with ink and shows a tick. The
/// touch target is 44 pt around it.
class OmiCheckRing extends StatelessWidget {
  const OmiCheckRing({super.key, required this.done, required this.onChanged, required this.semanticLabel});

  final bool done;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = OmiColors.textPrimary;
    return Semantics(
      checked: done,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: () => onChanged(!done),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          OmiHaptics.light();
          onChanged(!done);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? ink : Colors.transparent,
              border: Border.all(color: ink, width: 1.5),
            ),
            child: done ? OmiGlyph(OmiGlyphs.tick, size: 11, color: OmiColors.surface0) : null,
          ),
        ),
      ),
    );
  }
}

/// One row of [showOmiPopoverMenu].
class OmiMenuEntry<T> {
  const OmiMenuEntry(
      {required this.value,
      required this.label,
      this.glyph,
      this.icon,
      this.strong = false,
      this.dividerBefore = false,
      this.key});

  final T value;
  final String label;

  /// An [OmiGlyphs] path, or [icon] for a drawn one.
  final String? glyph;
  final Widget? icon;

  /// Bold (the menu's last, destructive row).
  final bool strong;
  final bool dividerBefore;
  final Key? key;
}

/// The v3 menu (`.menu`): a card under the header's right button, the page colour with a 1.5 pt ink
/// outline, 18 pt corners and a soft shadow; 46 pt rows with an 18 pt glyph. Resolves to the
/// picked value, or null when dismissed.
Future<T?> showOmiPopoverMenu<T>(BuildContext context, {required List<OmiMenuEntry<T>> entries}) {
  // `.menu`: 70 pt from the top, under the header's right button.
  final top = MediaQuery.paddingOf(context).top + 70;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, __) => Stack(
      children: [
        Positioned(
          top: top,
          left: 14,
          right: 14,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              key: const Key('omi_popover_menu'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: OmiColors.surface0,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x24000000), offset: Offset(0, 16), blurRadius: 40)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in entries) ...[
                    if (e.dividerBefore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, thickness: 1, color: OmiColors.divider),
                      ),
                    Semantics(
                      button: true,
                      label: e.label,
                      excludeSemantics: true,
                      onTap: () => Navigator.of(dialogContext).pop(e.value),
                      child: InkWell(
                        key: e.key,
                        onTap: () {
                          OmiHaptics.selection();
                          Navigator.of(dialogContext).pop(e.value);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: e.icon ??
                                    (e.glyph == null
                                        ? null
                                        : OmiGlyph(e.glyph!, size: 18, color: OmiColors.textPrimary)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: OmiType.callout.copyWith(
                                    height: 1.4,
                                    fontWeight: e.strong ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

/// A v3 list label (`h2`): 13/600 in the secondary ink, with an optional underlined link in ink on
/// the right edge. [top] and [bottom] are the space around the label; the link's touch target
/// fills that whole block so it stays tall enough while the words sit where the design puts them.
class OmiSectionLabel extends StatelessWidget {
  const OmiSectionLabel({
    super.key,
    required this.title,
    this.action,
    this.actionKey,
    this.onAction,
    this.top = 0,
    this.bottom = 6,
  });

  final String title;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;
  final double top;
  final double bottom;

  static TextStyle get style =>
      OmiType.footnote.copyWith(color: OmiColors.textSecondary, fontWeight: FontWeight.w600, height: 1.4);

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Semantics(header: true, child: Text(title, style: style)),
    );
    if (action == null || onAction == null) return label;
    return Stack(
      children: [
        Row(children: [Expanded(child: label)]),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: onAction,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                OmiHaptics.selection();
                onAction!();
              },
              child: Padding(
                padding: EdgeInsets.only(left: OmiSpacing.lg, top: top, bottom: bottom),
                child: Text(
                  action!,
                  key: actionKey,
                  style: style.copyWith(
                    color: OmiColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: OmiColors.textPrimary,
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

/// The v3 search field (`.sin`): a 42 pt pill with a 1.5 pt outline, the search glyph and 15 pt
/// words.
class OmiSearchPill extends StatelessWidget {
  const OmiSearchPill({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final text = OmiType.subhead.copyWith(height: 1.4);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(21)),
        border: Border.all(color: OmiColors.outline, width: 1.5),
      ),
      child: Row(
        children: [
          OmiGlyph(OmiGlyphs.searchLine, size: 15, color: OmiColors.faint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: text,
              cursorColor: OmiColors.textPrimary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: text.copyWith(color: OmiColors.faint),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).deleteButtonTooltip,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.cancel, size: 17, color: OmiColors.faint),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A row divider (`border-bottom: 1px solid var(--i08)`).
class OmiRowDivider extends StatelessWidget {
  const OmiRowDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, indent: indent, color: OmiColors.divider);
}

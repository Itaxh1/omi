import 'package:flutter/material.dart';

import 'package:omi/ui/components/omi_balanced_text.dart';
import 'package:omi/ui/components/omi_glyph.dart';
import 'package:omi/ui/omi_tokens.dart';

/// The body of a first-run step (v2): content from the top of the page under the progress bar,
/// left-aligned by default, and the step's buttons pinned to the bottom.
///
/// [content] scrolls when it does not fit (large text, small phones); [footer] (the step's
/// buttons) stays visible under it. The bottom system inset is reserved once, through [SafeArea].
///
/// ```dart
/// OnboardingStep(card: OnboardingCard(content: [...], footer: [OmiButton(...)]))
/// ```
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.content,
    this.footer = const [],
    this.padding = const EdgeInsets.fromLTRB(OmiSize.screenMargin, 0, OmiSize.screenMargin, 20),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  /// v2 insets running text 4pt further than the cards, fields and buttons at the page edge
  /// (text at 20pt, controls at 16pt). [OnboardingHeader] applies it; wrap other text with it.
  static const EdgeInsets textInset = EdgeInsets.zero;

  final List<Widget> content;
  final List<Widget> footer;
  final EdgeInsets padding;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: crossAxisAlignment,
                  children: content,
                ),
              ),
            ),
            // v3 `.obfoot`: 12 pt above, 10 pt between the buttons.
            if (footer.isNotEmpty) const SizedBox(height: 12),
            for (final (i, f) in footer.indexed) ...[if (i > 0 && f is! SizedBox) const SizedBox(height: 10), f],
          ],
        ),
      ),
    );
  }
}

/// A first-run step's heading (v2): the title in [OmiType.display] and an optional subtitle, inset
/// by [OnboardingCard.textInset].
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.title, this.subtitle});

  /// `.obh`: 30/600 at −.025em on a 1.12 line.
  static TextStyle get titleStyle => OmiType.pageTitle;

  /// `.obp`: 17 pt in the secondary ink on a 1.45 line.
  static TextStyle get bodyStyle =>
      OmiType.body.copyWith(fontWeight: FontWeight.w400, color: OmiColors.textSecondary, height: 1.45);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: OnboardingCard.textInset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // v3 `.obh` and `.obp`.
          Semantics(header: true, child: OmiBalancedText(title, style: OnboardingHeader.titleStyle)),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            OmiBalancedText(subtitle!, style: OnboardingHeader.bodyStyle),
          ],
        ],
      ),
    );
  }
}

/// A first-run step: the page under the back button and progress bar, filled by [card].
class OnboardingStep extends StatelessWidget {
  const OnboardingStep({super.key, required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    // Keep clear of the back ring and bars drawn over the top (12 + 40), then `.obbody`'s 26.
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 78),
      child: card,
    );
  }
}

/// A quiet link under a step's button (`.oblink`): 15 pt in the secondary ink, underlined, centred.
class OnboardingLink extends StatelessWidget {
  const OnboardingLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        link: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label,
              style: OmiType.subhead.copyWith(
                color: OmiColors.textSecondary,
                height: 1.4,
                decoration: TextDecoration.underline,
                decorationColor: OmiColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A step's picture (`.obicon`): an 84 pt ring in ink with the glyph inside.
class OnboardingIconRing extends StatelessWidget {
  const OnboardingIconRing({super.key, required this.glyph});

  /// An [OmiGlyphs] path.
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: OmiColors.textPrimary, width: 1.5)),
        child: OmiGlyph(glyph, size: 28, color: OmiColors.textPrimary),
      ),
    );
  }
}

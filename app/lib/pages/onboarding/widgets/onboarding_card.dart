import 'package:flutter/material.dart';

import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/components/omi_balanced_text.dart';
import 'package:omi/ui/components/omi_glyph.dart';
import 'package:omi/ui/omi_tokens.dart';
import 'package:omi/utils/l10n_extensions.dart';

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
              child: _StepEntrance(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: crossAxisAlignment,
                    children: content,
                  ),
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

/// A step's body coming in (`.obbody.in`, `obIn`): it fades in from 16 pt to the side over 0.38 s
/// when the step opens; the buttons under it stay put. Still under Reduce Motion.
class _StepEntrance extends StatefulWidget {
  const _StepEntrance({required this.child});

  final Widget child;

  @override
  State<_StepEntrance> createState() => _StepEntranceState();
}

class _StepEntranceState extends State<_StepEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _t = CurvedAnimation(parent: _in, curve: const Cubic(0.2, 0.8, 0.2, 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_in.isAnimating || _in.isCompleted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _in.value = 1;
    } else {
      _in.forward();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = Directionality.of(context) == TextDirection.rtl ? -16.0 : 16.0;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(side * (1 - _t.value), 0), child: child),
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

  /// `max-width: 32ch`: 32 widths of the body's "0" (or [style]'s), at the reader's text size.
  static double bodyMaxWidth(BuildContext context, [TextStyle? style]) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style ?? bodyStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width * 32;
    painter.dispose();
    return width;
  }

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
            // `.obp`: plain wrapping (the title balances, the body does not), at most 32ch wide.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: OnboardingHeader.bodyMaxWidth(context)),
              child: Text(subtitle!, style: OnboardingHeader.bodyStyle),
            ),
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

/// The line above a step's title (`.obk`): 13/600 in the secondary ink, 8 pt over the title.
class OnboardingKicker extends StatelessWidget {
  const OnboardingKicker(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: OmiType.footnote.copyWith(fontWeight: FontWeight.w600, color: OmiColors.textSecondary)),
    );
  }
}

/// The live dot (`.ld.on`): 8 pt of ink that fades to 30 % and back every 2.4 s while Omi listens.
class OnboardingLiveDot extends StatefulWidget {
  const OnboardingLiveDot({super.key, this.size = 8});

  final double size;

  @override
  State<OnboardingLiveDot> createState() => _OnboardingLiveDotState();
}

class _OnboardingLiveDotState extends State<OnboardingLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // `led`: 1 → 0.3 → 1, eased in and out.
        final t = Curves.easeInOut.transform(1 - (2 * _pulse.value - 1).abs());
        return Opacity(opacity: 1 - 0.7 * t, child: child);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: OmiColors.textPrimary),
      ),
    );
  }
}

/// "Listening on this phone  0:04" (`.obrec`): the live dot, what is listening at 15/600 and an
/// optional detail in the secondary ink.
class OnboardingListeningRow extends StatelessWidget {
  const OnboardingListeningRow({super.key, required this.label, this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final style = OmiType.subhead.copyWith(fontWeight: FontWeight.w600, height: 1.4);
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const OnboardingLiveDot(),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: style)),
          if (detail != null) ...[
            const SizedBox(width: 10),
            Text(
              detail!,
              style: style.copyWith(
                fontWeight: FontWeight.w400,
                color: OmiColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Bluetooth is off" (`.btw`), over the pendant steps while Bluetooth is off or not allowed: an
/// outlined card with the crossed-out glyph, why it matters, and Turn on. Hidden otherwise.
class OnboardingBluetoothBanner extends StatelessWidget {
  const OnboardingBluetoothBanner({super.key, this.show = false, this.onTurnOn});

  /// Shown whatever the adapter says (Bluetooth was declined with Not now).
  final bool show;

  /// Turn on; by default the system's Bluetooth prompt or settings.
  final VoidCallback? onTurnOn;

  static bool isOff(BluetoothAdapterState state) =>
      state == BluetoothAdapterState.off || state == BluetoothAdapterState.unauthorized;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BluetoothReadiness.instance,
      builder: (context, _) {
        if (!show && !isOff(BluetoothReadiness.instance.state)) return const SizedBox.shrink();
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            key: const Key('onboarding_bluetooth_off'),
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              color: OmiColors.surface0,
              border: Border.all(color: OmiColors.textPrimary, width: 1.5),
              borderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            // The glyph and words sit at the top; Turn on is centred on the card's height.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: OmiGlyph(OmiGlyphs.bluetoothOff, size: 18, color: OmiColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.bluetoothIsOff,
                            style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                        const SizedBox(height: 2),
                        Text(l10n.bluetoothOffOmiCantReach,
                            style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Align(
                    alignment: Alignment.center,
                    child: Semantics(
                      button: true,
                      child: GestureDetector(
                        key: const Key('onboarding_bluetooth_turn_on'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onTurnOn ?? () => BluetoothReadiness.instance.ensureReady(BluetoothUse.discovery),
                        // A 34 pt pill inside a 44 pt target.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: OmiColors.accent,
                              borderRadius: const BorderRadius.all(Radius.circular(17)),
                            ),
                            child: Text(l10n.turnOn,
                                style: OmiType.detail.copyWith(fontWeight: FontWeight.w600, color: OmiColors.onAccent)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// "What the light means" (v3 `lights`): the pendant's LED states, each a coloured dot, its name
/// and what it says. The dots are the LED's own colours, the one place v3 shows them.
Future<void> showLightLegend(BuildContext context) {
  final l10n = context.l10n;
  const red = Color(0xFFFF5A50); // omi-ux-allow: color-literal -- the pendant LED's red
  const blue = Color(0xFF5A8FFF); // omi-ux-allow: color-literal -- the pendant LED's blue
  const green = Color(0xFF34C759); // omi-ux-allow: color-literal -- the pendant LED's green
  final rows = [
    ([red], l10n.lightSolidRed, l10n.lightSolidRedMeaning),
    ([red], l10n.lightBlinkingRed, l10n.lightBlinkingRedMeaning),
    ([blue], l10n.lightSolidBlue, l10n.lightSolidBlueMeaning),
    ([green, red], l10n.lightGreenRed, l10n.lightGreenRedMeaning),
    ([green, blue], l10n.lightGreenBlue, l10n.lightGreenBlueMeaning),
    ([green], l10n.lightSolidGreen, l10n.lightSolidGreenMeaning),
  ];
  return showOmiSheet<void>(
    context: context,
    title: l10n.whatTheLightMeans,
    builder: (context) => SingleChildScrollView(
      child: Column(
        key: const Key('light_legend'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, row) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: OmiColors.divider)),
              ),
              child: Row(
                children: [
                  _Dot(colors: row.$1),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.$2, style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                        const SizedBox(height: 1),
                        Text(row.$3, style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A 12 pt LED dot; two colours split it down the middle (blinking between them).
class _Dot extends StatelessWidget {
  const _Dot({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.length == 1 ? colors.first : null,
        gradient: colors.length == 1
            ? null
            : LinearGradient(colors: [colors[0], colors[0], colors[1], colors[1]], stops: const [0, 0.5, 0.5, 1]),
      ),
    );
  }
}

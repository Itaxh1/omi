import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:omi/ui/components/omi_surface.dart';
import 'package:omi/ui/omi_tokens.dart';

/// The v2 floating material (tab bar, Ask button, header circles): a translucent fill (graphite,
/// or frosted white in daylight) over a saturated blur of whatever scrolls beneath it, lit on its top edge and casting a soft
/// shadow.
///
/// Blur is costly on low-end Android and unreadable for people who ask for more contrast, so it is
/// used only on Apple platforms without the high-contrast setting; everywhere else the surface is
/// solid [OmiColors.surface1]. Both look the same at rest.
class OmiGlass extends StatelessWidget {
  const OmiGlass({super.key, required this.borderRadius, required this.child, this.inHeader = false});

  final BorderRadius borderRadius;
  final Widget child;

  /// In a page header (the device chip, Search, the toolbar capsules): a tight shadow that stays
  /// inside the bar. The floating shadow is for the dock; in a header the bar cut it off into a
  /// grey block behind the chip in daylight.
  final bool inHeader;

  static bool _blurs(BuildContext context) {
    final platform = Theme.of(context).platform;
    final apple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return apple && !MediaQuery.highContrastOf(context);
  }

  // The design's `.glass`: rgba(30,34,43,.58) over blur 26 + saturate 170%, a soft top sheen, a
  // 0.5 pt top highlight and hairline ring, and a drop shadow outside the shape.
  static const List<OmiShadow> _shadows = [
    OmiShadow(color: Color(0x73000000), offset: Offset(0, 10), blur: 30),
    OmiShadow(color: Color(0x59000000), offset: Offset(0, 1), blur: 2),
  ];

  // Daylight (Liquid Dock light `--shadow`): a wide, faint ink shadow.
  static const List<OmiShadow> _shadowsLight = [
    OmiShadow(color: Color(0x2414171E), offset: Offset(0, 18), blur: 44),
    OmiShadow(color: Color(0x1414171E), offset: Offset(0, 1), blur: 3),
  ];

  // In a header: only the contact shadow, so the glass reads as sitting on the page.
  static const List<OmiShadow> _headerShadows = [OmiShadow(color: Color(0x59000000), offset: Offset(0, 1), blur: 3)];
  static const List<OmiShadow> _headerShadowsLight = [
    OmiShadow(color: Color(0x1A14171E), offset: Offset(0, 1), blur: 3),
    OmiShadow(color: Color(0x0D14171E), offset: Offset(0, 3), blur: 8),
  ];

  /// CSS `saturate(1.7)` as a colour matrix.
  static const double _s = 1.7;
  static const ColorFilter _saturate = ColorFilter.matrix(<double>[
    0.213 + 0.787 * _s, 0.715 - 0.715 * _s, 0.072 - 0.072 * _s, 0, 0, //
    0.213 - 0.213 * _s, 0.715 + 0.285 * _s, 0.072 - 0.072 * _s, 0, 0, //
    0.213 - 0.213 * _s, 0.715 - 0.715 * _s, 0.072 + 0.928 * _s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final blur = _blurs(context);
    final palette = OmiColors.palette;
    // A gradient replaces a decoration's colour, so the sheen is its own layer over the fill.
    final surface = DecoratedBox(
      decoration: BoxDecoration(color: blur ? palette.glass : palette.surface1, borderRadius: borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.glassSheen, palette.glassSheen.withValues(alpha: 0)],
            stops: const [0, 0.58],
          ),
        ),
        child: child,
      ),
    );
    return OmiSurfaceLight(
      borderRadius: borderRadius,
      shadows: inHeader
          ? (palette.isLight ? _headerShadowsLight : _headerShadows)
          : (palette.isLight ? _shadowsLight : _shadows),
      topLight: palette.glassRim,
      ring: palette.glassRing,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur
            ? BackdropFilter(
                filter: ui.ImageFilter.compose(outer: _saturate, inner: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26)),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

/// The v3 "3D grey glass" (the recorder card): a grey gradient lighter at the top-left over a blur
/// of the page, a bright hairline edge, and a two-layer soft shadow. 72–82 % opaque, so what
/// scrolls beneath cannot tint it. [radius] is 28 for the recorder card.
///
/// Like [OmiGlass], it blurs only on Apple platforms without the high-contrast setting; elsewhere
/// the gradient stands alone.
class OmiGlassCard extends StatelessWidget {
  const OmiGlassCard({super.key, required this.child, this.radius = OmiRadius.cardLarge, this.padding});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  // tokens.css `.glass-card`, light and dark.
  static const List<Color> _fillLight = [Color(0xD1EEEEF1), Color(0xBDDEDEE2), Color(0xB8D0D0D5)];
  static const List<Color> _fillDark = [Color(0xC74E4E54), Color(0xBD3A3A3F), Color(0xBD2C2C30)];
  static const Color _edgeLight = Color(0xB3FFFFFF);
  static const Color _edgeDark = Color(0x1FFFFFFF);
  static const List<BoxShadow> _shadowsLight = [
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 10), blurRadius: 24),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 24), blurRadius: 48),
  ];
  static const List<BoxShadow> _shadowsDark = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 10), blurRadius: 24),
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 24), blurRadius: 48),
  ];

  @override
  Widget build(BuildContext context) {
    final light = OmiColors.isLight;
    final borderRadius = BorderRadius.circular(radius);
    Widget body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light ? _fillLight : _fillDark,
          stops: const [0, 0.55, 1],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: light ? _edgeLight : _edgeDark),
      ),
      padding: padding,
      child: child,
    );
    if (OmiGlass._blurs(context)) {
      body = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 17, sigmaY: 17), child: body);
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: light ? _shadowsLight : _shadowsDark),
      child: ClipRRect(borderRadius: borderRadius, child: body),
    );
  }
}

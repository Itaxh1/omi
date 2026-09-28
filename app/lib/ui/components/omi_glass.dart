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

  // Where nothing blurs (Android, Increase Contrast) the same fill is laid over the page opaquely, so
  // what is behind the card never shows through its words.
  static const List<Color> _solidLight = [Color(0xFFF0EFF0), Color(0xFFE3E2E3), Color(0xFFD8D7D8)];
  static const List<Color> _solidDark = [Color(0xFF424247), Color(0xFF313135), Color(0xFF262629)];
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
    final blurs = OmiGlass._blurs(context);
    final borderRadius = BorderRadius.circular(radius);
    Widget body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: blurs ? (light ? _fillLight : _fillDark) : (light ? _solidLight : _solidDark),
          stops: const [0, 0.55, 1],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: light ? _edgeLight : _edgeDark),
      ),
      padding: padding,
      child: child,
    );
    if (blurs) {
      body = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 17, sigmaY: 17), child: body);
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: light ? _shadowsLight : _shadowsDark),
      child: ClipRRect(borderRadius: borderRadius, child: body),
    );
  }
}

/// The v3 plain glass (the top bar's 50 pt circles): the page's colour at 55 % (white at 8 % in
/// Black) over a 20 pt blur, a 1 pt outline, and nothing else: no shadow, no gloss, no inner line.
/// Presses scale to 0.93.
class OmiPlainGlassButton extends StatelessWidget {
  const OmiPlainGlassButton({
    super.key,
    required this.child,
    required this.label,
    required this.onPressed,
    this.size = 50,
  });

  final Widget child;

  /// The screen-reader name (and tooltip).
  final String label;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = OmiColors.palette;
    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.glass,
        shape: BoxShape.circle,
        border: Border.all(color: palette.glassRim),
      ),
      child: IconTheme.merge(data: IconThemeData(color: OmiColors.textPrimary), child: child),
    );
    if (OmiGlass._blurs(context)) {
      circle = ClipOval(
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: circle),
      );
    }
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
        child: circle,
      ),
    );
  }
}

/// The v8.2 liquid glass (the Ask bar, Your Omi's control dock): white at 62 % (graphite at 55 %
/// in Black) over a 30 pt saturated blur, a 1 pt bright edge, a 1 pt highlight along the top, a
/// hairline ring and a soft shadow. Solid where blur is off (other platforms, more contrast).
class OmiLiquidGlass extends StatelessWidget {
  const OmiLiquidGlass({super.key, required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  static const double _s = 1.8;
  static const ColorFilter _saturate = ColorFilter.matrix(<double>[
    0.213 + 0.787 * _s, 0.715 - 0.715 * _s, 0.072 - 0.072 * _s, 0, 0, //
    0.213 - 0.213 * _s, 0.715 + 0.285 * _s, 0.072 - 0.072 * _s, 0, 0, //
    0.213 - 0.213 * _s, 0.715 - 0.715 * _s, 0.072 + 0.928 * _s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final light = OmiColors.palette.isLight;
    final blur = OmiGlass._blurs(context);
    // The mock's `.askw` / `.os4dock` layers, light and dark.
    final fill = light
        ? (blur ? const Color(0x9EFFFFFF) : const Color(0xF5FFFFFF))
        : (blur ? const Color(0x8C2C2C30) : const Color(0xFF2C2C30));
    final edge = light ? const Color(0xD9FFFFFF) : const Color(0x1FFFFFFF);
    final highlight = light ? const Color(0xF2FFFFFF) : const Color(0x1AFFFFFF);
    final shadows = light
        ? const [
            BoxShadow(color: Color(0x12000000), spreadRadius: 0.5),
            BoxShadow(color: Color(0x1A000000), offset: Offset(0, 10), blurRadius: 30),
          ]
        : const [BoxShadow(color: Color(0x73000000), offset: Offset(0, 10), blurRadius: 30)];
    final surface = DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: borderRadius, border: Border.all(color: edge)),
      child: Stack(
        children: [
          child,
          // `inset 0 1px 0`: the top highlight inside the edge.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: IgnorePointer(child: ColoredBox(color: highlight)),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur
            ? BackdropFilter(
                filter: ui.ImageFilter.compose(outer: _saturate, inner: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30)),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

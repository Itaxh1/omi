import 'package:flutter/material.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/ui/omi_tokens.dart';

/// Shows a modal bottom sheet in the app's one sheet shell and returns its result.
///
/// The shell: [OmiColors.sheet] with 40pt (iOS) / 28pt (Android) top corners, the framework drag handle (36x4, which
/// screen readers can activate to dismiss), an optional title row with a trailing
/// [OmiCloseButton], bottom safe-area padding, and padding for the keyboard so text fields stay
/// visible. Content that does not fit scrolls if it is (or contains) a scrollable; wrap a long
/// `Column` in a `SingleChildScrollView`.
///
/// ```dart
/// final folder = await showOmiSheet<Folder>(
///   context: context,
///   title: l10n.moveToFolder,
///   builder: (context) => FolderPicker(...),
/// );
/// ```
///
/// Migrating an existing sheet: delete its hand-drawn handle, title row and close X, and pass its
/// title here. Sheets are dismissed by the X, a swipe down, or a tap on the scrim; set
/// [isDismissible]/[enableDrag] to false only while an irreversible operation runs.
Future<T?> showOmiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool showCloseButton = true,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
  RouteSettings? routeSettings,
}) {
  return showOmiModalSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    // v3 sheets have no handle: the title row and Done say what it is and how to leave; a swipe
    // down still closes it.
    showDragHandle: false,
    color: () => OmiColors.sheet,
    shape: RoundedRectangleBorder(borderRadius: OmiRadius.sheetTopFor(Theme.of(context).platform)),
    builder: (sheetContext) => OmiSheetScaffold(
      title: title,
      showCloseButton: showCloseButton,
      padding: padding,
      child: Builder(builder: builder),
    ),
  );
}

/// `showModalBottomSheet` for the Omi palette: the sheet's [color] is read each time it paints,
/// so switching light/dark while a sheet is open (Settings → Appearance) repaints the sheet itself
/// along with its content. The framework's route keeps the colour it was opened with, which left
/// Settings dark behind light cards after a switch.
Future<T?> showOmiModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Color Function() color,
  required ShapeBorder shape,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _OmiModalSheetRoute<T>(
      color: color,
      builder: builder,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      isDismissible: isDismissible,
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      settings: routeSettings,
      useSafeArea: useSafeArea,
    ),
  );
}

class _OmiModalSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _OmiModalSheetRoute({
    required this.color,
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.shape,
    super.clipBehavior,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    required super.isScrollControlled,
    super.settings,
    super.useSafeArea,
  });

  final Color Function() color;

  @override
  Color? get backgroundColor => color();
}

/// The inside of an Omi sheet: optional title row with a trailing close X, the content, and the
/// bottom safe-area and keyboard insets.
///
/// [showOmiSheet] wraps its builder in this already. Use it directly only when a sheet must be
/// presented some other way (a `DraggableScrollableSheet`, a nested navigator) but should look
/// the same.
class OmiSheetScaffold extends StatelessWidget {
  const OmiSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.showCloseButton = true,
    this.onClose,
    this.padding = const EdgeInsets.symmetric(horizontal: OmiSpacing.md),
  });

  final Widget child;

  /// Sheet title (Title Case). Without a title and without a close button, no header is drawn.
  final String? title;

  final bool showCloseButton;

  /// Close action; defaults to popping the sheet.
  final VoidCallback? onClose;

  /// Padding around [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || showCloseButton;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // v8.10 `.sheet`: a faint 8 % hairline along the rounded top edge (the shadow is the route's).
    return CustomPaint(
      foregroundPainter: _SheetTopEdge(color: OmiColors.textPrimary.withValues(alpha: 0.08), radius: OmiRadius.sheet),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasHeader)
                // `.sh`: 20 pt above, the title at 20/600, Done on the right, 12 pt below.
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(OmiSize.screenMargin, 20, OmiSize.screenMargin, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Semantics(
                                header: true,
                                child: Text(
                                  title!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: OmiType.title3
                                      .copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.4),
                                ),
                              ),
                      ),
                      if (showCloseButton) ...[
                        const SizedBox(width: OmiSpacing.sm),
                        OmiDonePill(onPressed: onClose ?? () => Navigator.of(context).maybePop()),
                      ],
                    ],
                  ),
                ),
              Flexible(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Done" (`.x`): a 34 pt pill with a 1.5 pt ink outline, 14/600. Closes a v3 sheet.
class OmiDonePill extends StatelessWidget {
  const OmiDonePill({super.key, required this.onPressed, this.label});

  final VoidCallback onPressed;

  /// Defaults to Done.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final done = label ??
        Localizations.of<AppLocalizations>(context, AppLocalizations)?.done ??
        MaterialLocalizations.of(context).closeButtonLabel;
    return Semantics(
      button: true,
      label: done,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('sheet_done'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            // v8.10 `.x`: the warm tone with a 9 % outline.
            decoration: BoxDecoration(
              color: OmiColors.tone,
              borderRadius: OmiRadius.pillAll,
              border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.09)),
            ),
            child: Text(
              done,
              style: OmiType.subhead.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2), // omi-ux-allow: font-size-literal -- the design's 14 pt Done
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline along a sheet's rounded top edge.
class _SheetTopEdge extends CustomPainter {
  _SheetTopEdge({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 1.0;
    final r = radius - w / 2;
    final path = Path()
      ..moveTo(w / 2, radius)
      ..arcToPoint(Offset(radius, w / 2), radius: Radius.circular(r))
      ..lineTo(size.width - radius, w / 2)
      ..arcToPoint(Offset(size.width - w / 2, radius), radius: Radius.circular(r));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  @override
  bool shouldRepaint(_SheetTopEdge old) => old.color != color || old.radius != radius;
}

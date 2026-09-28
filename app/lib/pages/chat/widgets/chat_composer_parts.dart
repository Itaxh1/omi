import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import 'package:omi/providers/message_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

// Pieces of the chat composer that carry no page state. The text field and the Send button stay
// in `chat/page.dart`: they are the catalogued controls (omi.chat.input / omi.chat.send), keyed there.

/// v3: the composer draws no shadow (the field is outlined).
List<BoxShadow> get kChatComposerShadow => const [];

/// The 44 pt ink circle beside the composer (v3 `.comp .cbtn`, which keeps `.comp button`'s ink
/// fill under a 1.5 pt rim): Add (idle) or Discard (recording).
///
/// Labelled for screen readers and long-press; [onPressed] null draws it disabled.
class ChatComposerSideButton extends StatelessWidget {
  const ChatComposerSideButton({super.key, required this.icon, required this.label, required this.onPressed});

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: OmiPressable(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: enabled ? OmiColors.accent : OmiColors.surface3,
              shape: BoxShape.circle,
              border: Border.all(color: OmiColors.outline, width: 1.5),
            ),
            child: Center(
              child: ExcludeSemantics(
                child: IconTheme.merge(
                  data: IconThemeData(color: enabled ? OmiColors.onAccent : OmiColors.textDisabled, size: 18),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round 38 pt button inside the composer pill (mic, send-while-recording), in a 44 pt target.
///
/// A disabled button is visibly disabled: a dark fill and a dimmed glyph instead of the white
/// "ready" fill. The glyph is a widget (FontAwesome `arrowUp` / `microphone`, like the side
/// button's `plus`), 16 pt and tinted through [IconTheme].
class ChatComposerRoundButton extends StatelessWidget {
  const ChatComposerRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.filled = true,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  /// An ink circle (the design's mic, and stop / send while recording); false leaves the glyph bare.
  final bool filled;

  /// Key for the tappable widget itself (automation addresses it).
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: OmiPressable(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: kOmiMinTapTarget,
            child: Center(
              child: AnimatedContainer(
                duration: OmiMotion.of(context).quick,
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: filled ? (enabled ? OmiColors.accent : OmiColors.surface3) : null,
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: filled ? 16 : 20,
                      color: !enabled
                          ? OmiColors.textDisabled
                          : filled
                              ? OmiColors.onAccent
                              : OmiColors.textPrimary,
                    ),
                    child: Center(child: icon),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send (v3 `#send`): a 52 pt ink circle with the up arrow. It does nothing until there is something
/// to send (and says so to screen readers).
class ChatSendButton extends StatelessWidget {
  const ChatSendButton({super.key, required this.buttonKey, required this.label, required this.onPressed});

  /// The tappable's key (the page passes the catalogued `omi.chat.send`).
  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: OmiPressable(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: OmiColors.accent, shape: BoxShape.circle),
          child: OmiGlyph(OmiGlyphs.send, size: 18, color: OmiColors.onAccent),
        ),
      ),
    );
  }
}

/// Thumbnails of the files picked for the next message, each with a labelled remove control and
/// a spinner while it uploads.
class ChatSelectedFilesStrip extends StatelessWidget {
  const ChatSelectedFilesStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageProvider>(
      builder: (context, provider, child) {
        if (provider.selectedFiles.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: OmiSpacing.md, bottom: OmiSpacing.xs),
          // Align with the chat bar's left edge: outer padding (8) + side button (48) + gap (8).
          padding: const EdgeInsets.only(left: 64, right: OmiSpacing.xs),
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: provider.selectedFiles.length,
            itemBuilder: (context, index) {
              final file = provider.selectedFiles[index];
              final isImage = provider.selectedFileTypes[index] == 'image';
              return Container(
                margin: const EdgeInsets.only(right: OmiSpacing.xs),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: OmiColors.surface2,
                  borderRadius: OmiRadius.lgAll,
                  image: isImage ? DecorationImage(image: FileImage(file), fit: BoxFit.cover) : null,
                ),
                child: Stack(
                  children: [
                    if (!isImage) Center(child: Icon(Icons.insert_drive_file, color: OmiColors.textPrimary, size: 24)),
                    if (provider.isFileUploading(file.path))
                      Container(
                        decoration: BoxDecoration(
                          color: OmiColors.surface0.withValues(alpha: 0.5),
                          borderRadius: OmiRadius.lgAll,
                        ),
                        child: const Center(child: OmiSpinner(size: OmiSpinnerSize.small)),
                      ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _RemoveFileButton(onPressed: () => provider.clearSelectedFile(index)),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RemoveFileButton extends StatelessWidget {
  const _RemoveFileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.removeAttachment;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          // The glyph is small so it does not cover the thumbnail; the target is the full 44 pt.
          child: SizedBox.square(
            dimension: kOmiMinTapTarget,
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.all(OmiSpacing.xxs),
                decoration: BoxDecoration(color: OmiColors.accent, shape: BoxShape.circle),
                child: Center(child: FaIcon(FontAwesomeIcons.xmark, size: 10, color: OmiColors.onAccent)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

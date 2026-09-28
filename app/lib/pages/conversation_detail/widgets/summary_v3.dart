import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';

/// A conversation's summary as the v3 mock sets it (`.sum`): headings at 17/600, bullets at 17 pt
/// on a 1.5 line in the 80 % ink, paragraphs the same. Reads the summary's markdown: `#` headings,
/// `-`/`*`/`•`/`1.` bullets, `**bold**`, blank lines.
class SummaryV3 extends StatelessWidget {
  const SummaryV3({super.key, required this.markdown});

  final String markdown;

  static final RegExp _heading = RegExp(r'^#{1,6}\s+');
  static final RegExp _bullet = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final body = OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.ink80);
    final heading = OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.4);
    final children = <Widget>[];
    var first = true;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (_heading.hasMatch(line)) {
        children.add(Padding(
          padding: EdgeInsets.only(top: first ? 18 : 26, bottom: 6),
          child: Semantics(header: true, child: Text(_plain(line.replaceFirst(_heading, '')), style: heading)),
        ));
      } else if (_bullet.hasMatch(line)) {
        final text = line.replaceFirst(_bullet, '');
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text('•', style: body.copyWith(color: OmiColors.textPrimary)),
              ),
              Expanded(child: Text.rich(_spans(text), style: body)),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: EdgeInsets.only(top: first ? 18 : 8, bottom: 4),
          child: Text.rich(_spans(line.trim()), style: body),
        ));
      }
      first = false;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  static String _plain(String text) => text.replaceAllMapped(_bold, (m) => m.group(1)!);

  static TextSpan _spans(String text) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w600)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }
}

/// One line of a summary being edited: a heading, a bullet or a paragraph, with its words.
class _DraftLine {
  _DraftLine(this.kind, String text, this.marker) : controller = TextEditingController(text: text);

  final _DraftKind kind;

  /// The line's markdown lead ("## ", "- ", "1. "), kept as it was.
  final String marker;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
}

enum _DraftKind { heading, bullet, paragraph }

/// A summary being edited in place (v8.18): its headings, bullets and paragraphs as editable lines,
/// written back to the same markdown ([toMarkdown]).
class SummaryDraft {
  SummaryDraft(String markdown) {
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final heading = SummaryV3._heading.firstMatch(line);
      final bullet = SummaryV3._bullet.firstMatch(line);
      if (heading != null) {
        _lines.add(_DraftLine(_DraftKind.heading, SummaryV3._plain(line.substring(heading.end)), heading.group(0)!));
      } else if (bullet != null) {
        _lines.add(_DraftLine(_DraftKind.bullet, line.substring(bullet.end), bullet.group(0)!));
      } else {
        _lines.add(_DraftLine(_DraftKind.paragraph, line.trim(), ''));
      }
    }
  }

  final List<_DraftLine> _lines = [];

  /// The edited summary as markdown; emptied lines are dropped.
  String toMarkdown() {
    final out = <String>[];
    for (final l in _lines) {
      final text = l.controller.text.trim().replaceAll('\n', ' ');
      if (text.isEmpty) continue;
      if (l.kind == _DraftKind.heading && out.isNotEmpty) out.add('');
      out.add('${l.marker}$text');
    }
    return out.join('\n');
  }

  /// Puts the cursor at the end of the first bullet (or line), as the design does.
  void focusFirst() {
    final first = _lines.firstWhere((l) => l.kind != _DraftKind.heading, orElse: () => _lines.first);
    first.focus.requestFocus();
    first.controller.selection = TextSelection.collapsed(offset: first.controller.text.length);
  }

  bool get isEmpty => _lines.isEmpty;

  void dispose() {
    for (final l in _lines) {
      l.controller.dispose();
      l.focus.dispose();
    }
  }
}

/// The summary in edit mode (`.sum.editing`): the same layout as [SummaryV3], each line editable;
/// bullets sit on the warm tone and the line being edited gets a 1.5 pt ink ring.
class SummaryV3Editor extends StatelessWidget {
  const SummaryV3Editor({super.key, required this.draft});

  final SummaryDraft draft;

  @override
  Widget build(BuildContext context) {
    final body = OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.ink80);
    final heading = OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.4);
    final children = <Widget>[];
    var first = true;
    for (final line in draft._lines) {
      final isHeading = line.kind == _DraftKind.heading;
      final field = _EditableLine(line: line, style: isHeading ? heading : body, filled: !isHeading);
      if (isHeading) {
        children.add(Padding(padding: EdgeInsets.only(top: first ? 18 : 26, bottom: 6), child: field));
      } else if (line.kind == _DraftKind.bullet) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('•', style: body.copyWith(color: OmiColors.textPrimary)),
                ),
              ),
              Expanded(child: field),
            ],
          ),
        ));
      } else {
        children.add(Padding(padding: EdgeInsets.only(top: first ? 18 : 8, bottom: 4), child: field));
      }
      first = false;
    }
    return Column(key: const Key('summary_editor'), crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _EditableLine extends StatefulWidget {
  const _EditableLine({required this.line, required this.style, required this.filled});

  final _DraftLine line;
  final TextStyle style;
  final bool filled;

  @override
  State<_EditableLine> createState() => _EditableLineState();
}

class _EditableLineState extends State<_EditableLine> {
  @override
  void initState() {
    super.initState();
    widget.line.focus.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.line.focus.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.line.focus.hasFocus;
    final fill = focused
        ? Color.alphaBlend(OmiColors.textPrimary.withValues(alpha: 0.07), OmiColors.surface0)
        : widget.filled
            ? OmiColors.tone
            : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: focused ? OmiColors.textPrimary : Colors.transparent, width: 1.5),
      ),
      child: TextField(
        controller: widget.line.controller,
        focusNode: widget.line.focus,
        style: widget.style,
        maxLines: null,
        cursorColor: OmiColors.textPrimary,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
      ),
    );
  }
}

/// The bar while the summary is edited (`.edbar`): ink, "Editing summary", Cancel and Save (paper).
class SummaryEditBar extends StatelessWidget {
  const SummaryEditBar(
      {super.key,
      required this.label,
      required this.cancel,
      required this.save,
      required this.onCancel,
      required this.onSave});

  final String label;
  final String cancel;
  final String save;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final paper = OmiColors.surface0;
    Widget button(String text, VoidCallback onTap, {required bool filled, required Key key}) => Semantics(
          button: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              OmiHaptics.selection();
              onTap();
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? paper : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(19)),
              ),
              child: Text(text,
                  style: OmiType.detail
                      .copyWith(fontWeight: FontWeight.w600, color: filled ? OmiColors.textPrimary : paper)),
            ),
          ),
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: OmiMotion.of(context).standard == Duration.zero ? Duration.zero : const Duration(milliseconds: 250),
      builder: (context, t, child) =>
          Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child)),
      child: Container(
        key: const Key('summary_edit_bar'),
        padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        decoration: BoxDecoration(
          color: OmiColors.accent,
          borderRadius: const BorderRadius.all(Radius.circular(26)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), offset: const Offset(0, 12), blurRadius: 30)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: OmiType.detail.copyWith(fontWeight: FontWeight.w500, color: paper)),
            ),
            button(cancel, onCancel, filled: false, key: const Key('summary_edit_cancel')),
            const SizedBox(width: 8),
            button(save, onSave, filled: true, key: const Key('summary_edit_save')),
          ],
        ),
      ),
    );
  }
}

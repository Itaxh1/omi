import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/settings/language_selection_dialog.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/user_provider.dart';
import 'package:omi/services/auth_service.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

class NameWidget extends StatefulWidget {
  final Function goNext;

  const NameWidget({super.key, required this.goNext});

  @override
  State<NameWidget> createState() => _NameWidgetState();
}

class _NameWidgetState extends State<NameWidget> {
  late TextEditingController nameController;
  var focusNode = FocusNode();

  @override
  void initState() {
    nameController = TextEditingController(text: SharedPreferencesUtil().givenName);
    super.initState();

    // Auto-focus the name input field after the widget is built
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   focusNode.requestFocus();
    // });
  }

  @override
  void dispose() {
    nameController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  bool get _canContinue => nameController.text.trim().isNotEmpty;

  /// The notes' language: the one already chosen, else the phone's own when Omi transcribes it.
  (String code, String name)? _language(HomeProvider home) {
    final languages = home.availableLanguages;
    final saved = SharedPreferencesUtil().userPrimaryLanguage;
    String? code = saved.isNotEmpty ? saved : null;
    if (code == null) {
      final device = Platform.localeName.split('_').first.toLowerCase();
      for (final entry in languages.entries) {
        final c = entry.value.toLowerCase();
        if (c == device || c.startsWith('$device-')) {
          code = entry.value;
          break;
        }
      }
    }
    if (code == null) return null;
    for (final entry in languages.entries) {
      if (entry.value == code) return (code, entry.key);
    }
    return (code, code);
  }

  Future<void> _submit() async {
    if (!_canContinue) return;
    FocusManager.instance.primaryFocus?.unfocus();
    AuthService.instance.updateGivenName(nameController.text.trim());
    OmiHaptics.selection();
    // The language step folded in here: keep the shown language unless the reader changed it.
    final home = context.read<HomeProvider>();
    final language = _language(home);
    if (!SharedPreferencesUtil().hasSetPrimaryLanguage && language != null) {
      unawaited(home.updateUserPrimaryLanguage(language.$1, userProvider: context.read<UserProvider>()));
    }
    widget.goNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = _language(context.watch<HomeProvider>());
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          OnboardingHeader(title: l10n.whatShouldOmiCallYou, subtitle: l10n.nameFromAccount),
          const SizedBox(height: 22),
          // v3 `.obin`: 58 pt, a 1.5 pt ink outline, the name at 22/500.
          Container(
            height: 58,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              border: Border.all(color: OmiColors.textPrimary, width: 1.5),
            ),
            child: TextField(
              key: const Key('onboarding_name_field'),
              controller: nameController,
              focusNode: focusNode,
              style: OmiType.title2.copyWith(fontWeight: FontWeight.w500),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: OmiColors.textPrimary,
              decoration: InputDecoration(
                hintText: l10n.yourNamePlaceholder,
                hintStyle: OmiType.title2.copyWith(fontWeight: FontWeight.w500, color: OmiColors.faint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (language != null) ...[
            const SizedBox(height: 14),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${l10n.notesLanguage(language.$2)} ',
                    style: OmiType.subhead.copyWith(height: 1.45, color: OmiColors.textSecondary)),
                Semantics(
                  button: true,
                  label: l10n.change,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const Key('onboarding_language_change'),
                    onTap: () async {
                      await LanguageSelectionDialog.show(context, forceShow: true);
                      if (mounted) setState(() {});
                    },
                    child: Text(
                      l10n.change,
                      style: OmiType.subhead.copyWith(
                        height: 1.45,
                        color: OmiColors.textPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor: OmiColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_name_continue'),
            label: l10n.continueButton,
            expand: true,
            onPressed: _canContinue ? _submit : null,
          ),
        ],
      ),
    );
  }
}

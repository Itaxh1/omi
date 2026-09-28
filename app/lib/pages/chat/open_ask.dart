import 'package:flutter/widgets.dart';

import 'package:omi/pages/chat/page.dart';
import 'package:omi/ui/ui.dart';

/// Opens Ask the way the design does: it rises over the screen ([omiAskRoute]).
Future<void> openAsk(BuildContext context, ChatPage page) async {
  if (!context.mounted) return;
  await Navigator.of(context).push(omiAskRoute<void>(builder: (_) => page));
}

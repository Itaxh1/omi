# Background service plugin patches

These packages are pinned copies of pub.dev releases, with their upstream licenses.
The Dart implementations are unchanged except for whitespace cleanup. Local native
changes are listed below; trailing whitespace is normalized throughout the copies.

- `flutter_background_service_ios` 5.0.3: remember registration attempt/result, skip
  scheduling without a registered task and callback, complete tasks whose callback
  was disabled. The host registers its handler before application launch returns.
- `flutter_foreground_task` 10.0.0: use its existing early registration entry point,
  remember the actual registration result, and schedule only registered tasks.
  Its Android `ForegroundService.kt` also includes the repository's existing
  `scripts/patch_flutter_foreground_task.py` fixes for prompt foreground promotion
  and the stop-path deadline. Gradle reapplies that patch idempotently.

The early calls live in `ios/Runner/AppDelegate.swift`. Flutter's scene lifecycle
may replay plugin launch callbacks after launch or for another engine. The guards
make those callbacks harmless without replacing system scheduler methods or
discarding valid background submissions. Keep the patches when upgrading, or
remove these overrides when upstream provides equivalent scene-safe registration.

# Flutter fixes requested — 28 September 2026

Branch: `design/v3-mono`. Baseline before this work: `aafbc62b21`.
This is the request log and verification record. Checked means implemented in the
working tree; physical-device verification is listed separately below.

## Requests

- [x] Recheck the Flutter startup and onboarding regression against the redesign
  history and `Omi-v8-x.html`. The blank Home sizing fix already exists in the
  baseline; keep its regression test.
- [x] Fix startup retries, Firebase configuration error handling, Profile flavor
  plist selection, and production Google redirect IDs.
- [x] Replace the iOS background-task scheduler swizzle with early, idempotent
  registration in the two background-service plugins.
- [x] Monitor Bluetooth throughout onboarding, including phone validation and
  permissions; refresh after returning from Settings and allow retrying guidance.
  iOS requires the person to enable Bluetooth in system controls.
- [x] If the pendant disconnects or dies during “Say a few words”, stop claiming
  it is listening; offer reconnect, phone recording and skip. Bound the finish wait.
- [x] Warn at 5% battery or below even if the earlier low-battery warning fired.
- [x] Show the first recording while it is transcribing; keep unfinished notes
  closed until they are ready and avoid duplicates when processing completes.
- [x] Exercise the entire first-recording onboarding navigation with synthetic I/O: speak a
  reminder (for example “Remind me to call Sam tomorrow”), finish capture, show
  its processed title/summary/task, continue to Teach Omi your voice, read all
  three lines, save the voice profile, reach “You're set”, and Open Omi.
  Tests must cover arbitrary reminder content, waiting/failed processing, skip,
  disconnected devices and microphone failures; never create a demo task merely
  because the example sentence is displayed.
- [x] Add a first-day welcome note from the Omi developers with thanks and Discord.
- [x] Restore the microphone inside the Ask Anything chat composer. Transcribe to
  editable text; safely pause/resume phone capture when dictation needs its mic.
- [x] Make dark Home completely black.
- [x] Increase both Home pull activation distances by 40%.
- [x] Make “Firmware up to date” a normal Devices row, like Double tap.
- [x] Show five Home conversations on roomy screens, three on small screens or
  with large text/limited available height.
- [x] Ask once before deleting a conversation list item, using a monochrome
  confirmation. Cancel keeps the item; confirmed deletion still offers Undo.
- [x] Paint the task editor surface behind the keyboard’s rounded corners to
  remove the black gap in `IMG_1215.PNG`.
- [x] Compare and restore the earlier notification/Lock Screen and Dynamic Island
  waveform appearance and motion from the v2 history: `b7475aa32e` blue five-bar
  compact/minimal indicator and 26-point Lock Screen wave.
  Preserve the current monochrome card, source labels and working capture controls.
  Stale/paused sources stop looking live; Reduce Motion disables the ripple.
  The user explicitly selected this early v2 version.
- [x] Follow-up reference: `omi-liquid-dock2.html` supplies the waveform motion.
  Correct the native four-second cycle to its 1.6-second CSS ease-in-out pulse,
  45% midpoint scale and 130 ms adjacent-bar stagger. Scale short bars after
  clamping their base height, so they keep pulsing. Keep the blue compact mark.
  Native Live Activities interpolate received updates; they do not run the
  HTML's continuous animation clock. Phone motion comparison remains separate.
- [x] Follow-up: show a distinct `Untitled draft` immediately for each recording;
  when stopped show `Generating…`, keep it unavailable until ready, and replace
  it with the completed conversation without duplicates.
- [x] Improve the Omi pendant icon used in conversation list rows so it reads
  clearly at its small size and suits both black and white themes.
- [x] Home folder, account and Ask anything: neutral liquid-glass contour, soft reflection; existing colours, size, content and gestures preserved. High-contrast retains the plain finish.
- [x] Finish focused regression, native build and visual checks.
- Delivery requested: commit these fixes, push to `origin/design/v3-mono`, and
  open its GitHub link. The final handoff includes the pushed commit link.

## Findings behind the fixes

- The blank Home layout correction already exists at the starting revision. The
  screenshot alone cannot establish which startup failure happened on the phone.
  Additional startup defects found here were a non-retryable `late final` Env
  singleton, uncategorized Firebase project validation failures, missing Profile
  flavor cases in plist-copy scripts, and mismatched production Google callbacks.
- The iOS workaround intercepted system background-task methods but could still
  attempt the first registration after launch. The plugins now register their
  actual handlers during launch, guard duplicate callbacks, and only submit
  registered tasks that have configured work.
- The first recording could continue displaying Listening after a pendant died.
  Its result baseline could also exclude the same in-progress conversation it
  needed to show. Both paths now track the current recording and connection.
- A prior low-battery warning could suppress the critical warning. Separate
  low/critical thresholds now permit a new warning at 5% without repeated alerts.

## Verification

- 172 focused Flutter tests passed (171 in the combined run, then the additional
  cross-day Home case and all ten Home list cases passed).
- 23 hermetic mobile journey checks passed.
- Android `:app:testDevDebugUnitTest` passed using JDK 21.
- iOS unsigned `Profile-prod` build passed, including the Watch target.
- Dart analyzer ratchet passed; focused analysis of the latest UI edits passed.
- Firebase flavor copy tests: 26 assertions; dev config tests: 38 assertions.
- Light/dark headless visual audits covered Home, chat, onboarding and Devices.
  These are synthetic Flutter renders, not screenshots of an installed phone build.
- A production-wrapper onboarding scenario covers the reminder transcript,
  processing response, summary and task, all three voice lines, successful
  enrollment, completion, and Home. It checks that the first note, welcome entry,
  and dated task are still available after dismissing the first-day tip.
- Native waveform checks compile the production Swift ripple and snapshot code;
  paused/stale/reconnecting sources and the HTML reference pulse samples pass.
- Full branch `make preflight` reaches an existing product-file line-count ratchet
  failure involving 32 files grown since `origin/main`. Do not call this gate green.
- The preflight metadata suggestion also identifies three pre-existing references
  to removed test files in the failure-class registry. These are branch-wide
  maintenance issues, not a passing check for this change.

## Test cases and coverage

| Request | Automated cases |
| --- | --- |
| Blank launch and retry | Home fills the screen without its first-run tip; Env can initialize again; duplicate Firebase initialization and invalid config paths |
| Native startup | Execute both plist-copy scripts for all six Debug/Profile/Release flavors; compile the full iOS app, widget and Watch targets |
| Bluetooth everywhere | Entry/resume checks; radio off/on; dismiss and reopen guidance; entered validation text survives a Bluetooth change |
| Dead pendant on first recording | Disconnect removes Listening immediately; phone fallback, rejected mic permission, skip and 12-second finish timeout |
| Battery | Initial 1%/5%, 20%-then-5% crossing, invalid readings, reconnect, charging reset and jitter without duplicate warnings |
| First reminder | Production wrapper navigates recording → processing → summary/task → voice intro → three lines → completion → Home using synthetic I/O |
| Real note/task content | An arbitrary processed reminder appears; ordinary speech without extracted tasks creates no sample Call Sam task; tapping the task calls the completion operation |
| Short reminder retention | Execute 57 existing backend relevance cases plus duration invariance and “Remind me to call Sam tomorrow” at 1, 3 and 6 seconds; all keep the reminder |
| Processing/Home | Pending note visible and disabled; completed note replaces it once; absent upload remains pending, discarded recording reports too short; delayed result allows continuation |
| Voice training | Three lines save at least five seconds of audio; Skip saves nothing; failed mic start and interruption exit safely; rejected enrollment never reports success |
| Welcome note | First-day entry opens the developer welcome with Discord |
| Ask Anything microphone | Composer mic starts dictation; transcript fills the draft; phone capture releases its mic and resumes only the same untouched session |
| Home gestures and list | Old shorter pulls do nothing; 40% longer pulls activate; roomy screen returns five notes, short/narrow/large-text screen returns three |
| Conversation delete | One monochrome confirmation on a full swipe; Cancel preserves item; confirmed delete offers Undo; Undo prevents server deletion |
| Task editor | Sheet material extends to the screen bottom under a 320-point keyboard inset; controls remain above it; successful/failed save and dirty-dismiss behavior |
| Native waveform | Compile production Swift ripple/snapshot code; check the HTML reference's 1.6-second period, CSS ease samples, 130 ms staggering, 13-bar phase repetition, pause/stale/reconnect states and unmetered ticks |

The reminder rule tests were run directly against the production module and the
existing test functions. The normal backend pytest command is unavailable in this
environment because its global conftest requires the missing `google.api_core`.
These tests do not claim live speech recognition or LLM extraction quality.

## Remaining physical checks

Reproduce a pendant battery disconnect during onboarding, an actual 5% notification,
Bluetooth off/on during validation, phone mic dictation handoff, and the native
Lock Screen/Dynamic Island animation on a signed iPhone build. Automated tests
and an unsigned build cannot establish these hardware results.


## Follow-up verification — drafts, wave reference and glass

- Live capture now projects one `Untitled draft` / `Recording` row into Home and
  Conversations. Stop retains its identity as `Generating…` before microphone
  teardown and before the final transcript arrives. Every pending recording is
  shown in All conversations; Home retains its five/three-row limit.
- Unique local IDs replace the shared production placeholder. Refresh never
  sends them to the server. A confirmed result replaces only its draft; a late
  processing response cannot revive an already completed note. Empty recordings
  and failed processing remove their local placeholder. Local/offline audio
  continues through the existing recordings/upload queue.
- 112 focused Flutter tests passed, including six new recording lifecycle cases
  and a local-ID refresh/account-clear case. The final follow-up run passed 17
  tests, including Home's original blank-screen layout regression.
- All 23 hermetic mobile journeys passed again. Analyzer ratchet and the native
  Swift waveform assertions passed. Generated localization checks run after
  Flutter's generation/format step.
- Inspected light/dark renders of Home, the recording draft, header controls and
  conversation rows. The generated raster icon lost definition at 25 points;
  the shipped pendant is a simplified SVG with consistent strokes and tint.
- `agent-flutter connect` could not find an active debug VM. Visual evidence here
  comes from the production-widget audit harness; it is not device interaction.
- `make preflight` again fails the branch-wide product-file size ratchet (32 files
  against `origin/main`); PR metadata is unavailable because this fork branch has
  no PR. This is not a green full preflight.
- Pairing was reported as working by the user; no speculative pairing changes
  were made in this follow-up.

## Follow-up — limit pull hints and clean iPhone install

- The pause and listening-again undo pop-ups share a three-display limit, saved
  across launches. Subsequent pulls still operate normally. Failed actions keep
  their error alert and do not consume the limit; calls do not consume it either.
- All 20 focused gesture, listening-label and recorder-action tests pass,
  including persistence across preferences reload and widget recreation.
- Analyzer ratchet and localization consistency checks pass.
- All 23 hermetic mobile journey checks pass again. Full preflight still fails
  the existing branch-wide file-size ratchet; it is not a green full preflight.
- Completed the clean install on Ashwin's iPhone on September 28, 2026. Verified
  deletion of this preview app's local Keychain items and shared widget data,
  uninstalled its container/cache, and installed signed build `09db62eb21`.
  No cloud account or server conversations were deleted. No local cache was
  restored. The clean install resets the hint count.
- Launched without a debugger and inspected the settled device screenshot:
  the initial welcome screen offers Apple/Google sign-in, with no saved session.
  Signed build, reset, uninstall, install and launch receipts are saved locally.

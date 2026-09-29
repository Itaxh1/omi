import 'package:omi/utils/platform/platform_manager.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/http/api/users.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/home/page.dart';
import 'package:omi/pages/home/widgets/welcome_note.dart';
import 'package:omi/pages/onboarding/ai_consent_widget.dart';
import 'package:omi/pages/onboarding/auth.dart';
import 'package:omi/pages/onboarding/name/name_widget.dart';
import 'package:omi/pages/onboarding/pick_device_step.dart';
import 'package:omi/pages/onboarding/permissions/permissions_checker.dart';
import 'package:omi/pages/onboarding/permissions/permissions_widget.dart';
import 'package:omi/pages/onboarding/complete_screen.dart';
import 'package:omi/pages/onboarding/first_conversation_steps.dart';
import 'package:omi/pages/onboarding/guided_voice_controller.dart';
import 'package:omi/pages/onboarding/pendant_steps.dart';
import 'package:omi/pages/onboarding/voice_steps.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_connection_monitor.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/services/auth_service.dart';
import 'package:omi/utils/analytics/intercom.dart';
import 'package:omi/utils/analytics/product_telemetry.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/app_globals.dart';
import 'package:omi/core/app_shell.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/auth/clear_user_state.dart';

class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({
    super.key,
    this.forceAuthPage = false,
    @visibleForTesting this.initialPage,
    @visibleForTesting this.initialWearable = false,
    @visibleForTesting this.voiceIO,
  });

  final bool forceAuthPage;

  /// The page to open on (the visual audit captures each step inside the wrapper's top row).
  @visibleForTesting
  final int? initialPage;

  /// Opens on the pendant path (the audit's pendant steps).
  @visibleForTesting
  final bool initialWearable;

  /// The microphone and upload behind "Read this out loud"; the audit passes a quiet one.
  @visibleForTesting
  final GuidedVoiceIO? voiceIO;

  /// Page indices, for [initialPage].
  static const int consentPage = _OnboardingWrapperState.kAiConsentPage;
  static const int namePage = _OnboardingWrapperState.kNamePage;
  static const int pickDevicePage = _OnboardingWrapperState.kPickDevicePage;
  static const int powerPage = _OnboardingWrapperState.kPowerPage;
  static const int bluetoothPage = _OnboardingWrapperState.kBluetoothPage;
  static const int scanPage = _OnboardingWrapperState.kScanPage;
  static const int buttonsPage = _OnboardingWrapperState.kButtonsPage;
  static const int permissionsPage = _OnboardingWrapperState.kPermissionsPage;
  static const int firstPage = _OnboardingWrapperState.kFirstPage;
  static const int resultPage = _OnboardingWrapperState.kResultPage;
  static const int voicePage = _OnboardingWrapperState.kVoicePage;
  static const int readPage = _OnboardingWrapperState.kReadPage;
  static const int completePage = _OnboardingWrapperState.kCompletePage;

  @override
  State<OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<OnboardingWrapper> with TickerProviderStateMixin {
  // Onboarding pages (0 is sign-in), as the v3 flows run: Welcome, Three things to know, What should
  // Omi call you, How will you record; then the pendant's setup (turn it on, Bluetooth, pair, its
  // button) or the phone's microphone; Say a few words, your first conversation, Teach Omi your
  // voice (and the lines to read), You're set.
  static const int kAiConsentPage = 1; // Data-and-AI disclosure with explicit consent
  static const int kNamePage = 2; // With the notes' language and Change
  static const int kPickDevicePage = 3; // How will you record?
  static const int kPowerPage = 4; // Pendant 1 of 3: turn it on
  static const int kBluetoothPage = 5; // Pendant: allow Bluetooth
  static const int kScanPage = 6; // Pendant 2 of 3: find and pair
  static const int kButtonsPage = 7; // Pendant 3 of 3: the button and the light
  static const int kPermissionsPage = 8; // Phone: the microphone
  static const int kFirstPage = 9; // Say a few words
  static const int kResultPage = 10; // Your first conversation
  static const int kVoicePage = 11; // Teach Omi your voice (optional)
  static const int kReadPage = 12; // Read this out loud
  static const int kCompletePage = 13; // "You're set" completion screen
  static const int kPageCount = 14;

  /// The steps a reopened app resumes at: the name, the recording choice (anything on the way to
  /// the first conversation starts again there), or the voice once the first conversation is done.
  static const List<int> kProgressSteps = [kNamePage, kPickDevicePage, kVoicePage];

  static int? _resumePointFor(int page) => switch (page) {
        kNamePage => kNamePage,
        kPickDevicePage ||
        kPowerPage ||
        kBluetoothPage ||
        kScanPage ||
        kButtonsPage ||
        kPermissionsPage ||
        kFirstPage =>
          kPickDevicePage,
        kResultPage || kVoicePage || kReadPage => kVoicePage,
        _ => null,
      };

  /// The bars at the top (v3 `BAR`): consent, name, how you record, setting it up (the pendant's
  /// steps or the microphone), the first conversation, the voice.
  static int? barIndex(int page) => switch (page) {
        kAiConsentPage => 0,
        kNamePage => 1,
        kPickDevicePage => 2,
        kPowerPage || kBluetoothPage || kScanPage || kButtonsPage || kPermissionsPage => 3,
        kFirstPage || kResultPage => 4,
        kVoicePage => 5,
        _ => null,
      };
  static const int kBarCount = 6;

  /// The back ring shows on every step with bars but the first conversation (it is being written;
  /// its room is kept so the bars stay put), and alone over the lines to read.
  static bool showsBack(int page) => page == kReadPage || (barIndex(page) != null && page != kResultPage);

  /// Recording with a wearable (the pendant path) rather than this phone.
  late bool _wearable = widget.initialWearable;

  /// The conversations there were before the first recording: the new one is the one not in here.
  Set<String> _knownConversationIds = const {};

  /// The first recording was skipped: there is no first conversation to go back to.
  bool _firstSkipped = false;

  /// Not now on Turn on Bluetooth: the search waits for Turn on instead of asking.
  bool _bluetoothDeclined = false;

  TabController? _controller;
  bool get hasSpeechProfile => SharedPreferencesUtil().hasSpeakerProfile;
  ProductAttempt? _onboardingAttempt;

  @override
  void initState() {
    super.initState();
    if (!widget.forceAuthPage && !SharedPreferencesUtil().onboardingCompleted) {
      _onboardingAttempt = ProductTelemetry.instance.start(
        ProductJourney.onboarding,
        surface: ProductSurface.onboarding,
      );
    }
    _controller = TabController(length: kPageCount, vsync: this, initialIndex: widget.initialPage ?? 0);
    _controller!.addListener(() {
      if (!mounted) return;
      setState(() {});
      _rememberStep(_controller!.index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let's not update permissions here because of Apple's review process
      // if (mounted) {
      //   context.read<OnboardingProvider>().updatePermissions();
      // }

      if (widget.initialPage == null && !widget.forceAuthPage && AuthService.instance.isSignedIn()) {
        // && !SharedPreferencesUtil().onboardingCompleted
        if (mounted) {
          context.read<HomeProvider>().setupHasSpeakerProfile();
          // The consent gate is checked first and is independent of the
          // server-side onboardingCompleted flag. This ensures every user
          // — including someone signing back into a previously-onboarded
          // account on a fresh install — sees the consent screen at least
          // once before any AI processing begins.
          if (!SharedPreferencesUtil().aiConsentGiven) {
            _controller!.animateTo(kAiConsentPage);
          } else if (SharedPreferencesUtil().onboardingCompleted) {
            await _routeWithPermissionsCheck(context);
          } else {
            _controller!.animateTo(_resumeStep());
          }
        }
      }
      // If not signed in, it stays at the Auth page (index 0)
    });
  }

  @override
  void dispose() {
    _onboardingAttempt?.complete(ProductOutcome.unobserved, failure: ProductFailure.incomplete);
    _controller?.dispose();
    super.dispose();
  }

  void _completeOnboardingTelemetry() {
    _onboardingAttempt?.complete(ProductOutcome.success);
    _onboardingAttempt = null;
  }

  Future<void> _routeWithPermissionsCheck(BuildContext context) async {
    if (!SharedPreferencesUtil().permissionsCompleted) {
      final granted = await arePermissionsGranted();
      if (!granted) {
        if (context.mounted) {
          routeToPage(context, const PermissionsInterstitialPage(), replace: true);
        }
        return;
      }
      SharedPreferencesUtil().permissionsCompleted = true;
    }
    if (context.mounted) {
      routeToPage(context, const HomePageWrapper(), replace: true);
    }
  }

  void _goNext() {
    if (_controller!.index < _controller!.length - 1) {
      _controller!.animateTo(_controller!.index + 1);
    }
  }

  // ---- Resume and back ----------------------------------------------------------------------

  /// Per-account key so a different account signing in on this phone starts at the first step.
  String get _resumeKey => 'onboarding/resumeStep/${SharedPreferencesUtil().uid}';

  void _rememberStep(int index) {
    final point = _resumePointFor(index);
    if (widget.forceAuthPage || point == null) return;
    SharedPreferencesUtil().saveInt(_resumeKey, point);
  }

  /// The step to reopen after the app was killed mid-onboarding: the last step the reader reached,
  /// or the first question.
  int _resumeStep() {
    final saved = SharedPreferencesUtil().getInt(_resumeKey, defaultValue: kNamePage);
    return kProgressSteps.contains(saved) ? saved : kNamePage;
  }

  /// The step before the current one (the design's back), or null when there is nothing to go back
  /// to (Auth, consent, the first conversation, completion).
  int? get _previousStep => switch (_controller!.index) {
        kNamePage => kAiConsentPage,
        kPickDevicePage => kNamePage,
        kPowerPage => kPickDevicePage,
        kBluetoothPage => kPowerPage,
        kScanPage => kBluetoothPage,
        kButtonsPage => kScanPage,
        kPermissionsPage => kPickDevicePage,
        kFirstPage => _wearable ? kButtonsPage : kPermissionsPage,
        kVoicePage => _firstSkipped ? kFirstPage : kResultPage,
        kReadPage => kVoicePage,
        _ => null,
      };

  /// Back — the on-screen control, Android system back and the iOS swipe all land here.
  void _goBack() {
    final previous = _previousStep;
    if (previous == null) return;
    OmiHaptics.selection();
    _controller!.animateTo(previous);
  }

  void _goTo(int page) {
    if (page == kFirstPage && _controller!.index != kFirstPage) {
      // The pendant may already have an in-progress conversation from pairing.
      // Only completed history is old; never exclude the recording being finished.
      final conversations = context.read<ConversationProvider>();
      _knownConversationIds = {
        for (final c in conversations.conversations)
          if (c.status == ConversationStatus.completed) c.id,
      };
    }
    _controller!.animateTo(page);
  }

  /// The phone path's microphone step, unless the microphone is already allowed.
  Future<void> _toPhoneRecording() async {
    var granted = false;
    try {
      granted = await Permission.microphone.isGranted;
    } catch (_) {}
    if (mounted) _goTo(granted ? kFirstPage : kPermissionsPage);
  }

  /// "Omi knows your voice" once the reading is saved; a note when it could not be.
  void _voiceEnrolled(bool saved) {
    if (!mounted) return;
    if (saved) {
      SharedPreferencesUtil().hasSpeakerProfile = true;
      OmiFeedback.confirm(context, context.l10n.omiKnowsYourVoice);
    } else {
      OmiFeedback.info(context, context.l10n.voiceNotSavedV3);
    }
  }

  /// "Use a Different Account" on the consent step: sign out and start again from the beginning.
  Future<void> _useDifferentAccount() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final rootContext = globalNavigatorKey.currentContext;
    if (rootContext != null && rootContext.mounted) clearAllUserState(rootContext);
    await SharedPreferencesUtil().clear();
    await AuthService.instance.signOut();
    navigator.pushAndRemoveUntil(omiPageRoute(builder: (_) => const AppShell()), (_) => false);
  }

  /// The phone path ends listening with this phone (v3 `obFinish`), unless it already is.
  void _startPhoneListening() {
    final capture = context.read<CaptureProvider>();
    if (capture.liveCaptureSource != null) return;
    capture.streamRecording().then((_) {}, onError: (Object e) {
      // Home shows Start listening; nothing is lost.
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = _controller!.index;
    List<Widget> pages = [
      AuthComponent(
        onSignIn: () async {
          if (!mounted) return;
          PlatformManager.instance.analytics.onboardingStepCompleted('Auth');
          context.read<HomeProvider>().setupHasSpeakerProfile();
          // Refresh subscription on sign-in: AppShell only fetches it on mount,
          // so an in-session re-login would otherwise leave it null until the
          // Plan & Usage page is opened (missing Pro badge).
          context.read<UsageProvider>().fetchSubscription();
          IntercomManager.instance.loginIdentifiedUser(SharedPreferencesUtil().uid);
          // Consent is checked first regardless of server-side onboarding
          // state so a returning user signing in on a fresh install still
          // sees the consent screen before any AI processing begins.
          if (!SharedPreferencesUtil().aiConsentGiven) {
            _controller!.animateTo(kAiConsentPage);
          } else if (SharedPreferencesUtil().onboardingCompleted) {
            await _routeWithPermissionsCheck(context);
          } else {
            _controller!.animateTo(_resumeStep());
          }
        },
      ),
      AiConsentWidget(
        onAgree: () async {
          if (!mounted) return;
          SharedPreferencesUtil().aiConsentGiven = true;
          PlatformManager.instance.analytics.onboardingStepCompleted('AI Consent');
          // If the server says this user already completed onboarding, jump
          // straight to home — their first-time onboarding ran in a previous
          // session and we don't want to re-run it.
          if (SharedPreferencesUtil().onboardingCompleted) {
            await _routeWithPermissionsCheck(context);
          } else {
            _controller!.animateTo(_resumeStep());
          }
        },
        onUseDifferentAccount: _useDifferentAccount,
      ),
      NameWidget(
        goNext: () {
          _goNext(); // How will you record?
          IntercomManager.instance.updateUser(
            FirebaseAuth.instance.currentUser!.email,
            FirebaseAuth.instance.currentUser!.displayName,
            FirebaseAuth.instance.currentUser!.uid,
          );
          PlatformManager.instance.analytics.onboardingStepCompleted('Name');
        },
      ),
      OnboardingPickDeviceStep(
        wearable: _wearable,
        goNext: (wearable) {
          setState(() => _wearable = wearable);
          PlatformManager.instance.analytics.onboardingStepCompleted('Pick Device');
          if (wearable) {
            _goTo(kPowerPage);
          } else {
            _goTo(kPermissionsPage);
          }
        },
      ),
      OnboardingPowerStep(onOn: () => _goTo(kBluetoothPage)),
      OnboardingBluetoothStep(
        onNext: (allowed) {
          _bluetoothDeclined = !allowed;
          _goTo(kScanPage);
        },
      ),
      // Built only while it shows: it scans from the moment it opens.
      index == kScanPage
          ? OnboardingScanStep(
              bluetoothDeclined: _bluetoothDeclined,
              onPaired: () => _goTo(kButtonsPage),
              onUsePhone: () {
                setState(() => _wearable = false);
                _toPhoneRecording();
              },
            )
          : const SizedBox.shrink(),
      OnboardingButtonsStep(onDone: () => _goTo(kFirstPage)),
      PermissionsWidget(
        goNext: () {
          PlatformManager.instance.analytics.onboardingStepCompleted('Permissions');
          _goTo(kFirstPage);
        },
      ),
      // The first recording listens only while it shows.
      index == kFirstPage
          ? OnboardingFirstWordsStep(
              wearable: _wearable,
              onUsePhone: () => setState(() => _wearable = false),
              onReconnect: () => _goTo(kScanPage),
              onDone: () {
                _firstSkipped = false;
                _goTo(kResultPage);
              },
              onSkip: () {
                _firstSkipped = true;
                _goTo(kVoicePage);
              },
            )
          : const SizedBox.shrink(),
      index == kResultPage
          ? OnboardingFirstResultStep(
              knownIds: _knownConversationIds,
              wearable: _wearable,
              onContinue: () => _goTo(kVoicePage),
            )
          : const SizedBox.shrink(),
      OnboardingVoiceIntroStep(
        onStart: () => _goTo(kReadPage),
        onLater: () {
          PlatformManager.instance.analytics.speechProfileSkipped();
          _goTo(kCompletePage);
        },
      ),
      index == kReadPage && !widget.forceAuthPage
          ? OnboardingVoiceReadStep(
              io: widget.voiceIO,
              onDone: () {
                // Continued is not enroll success (#12765): the upload reports on its own.
                PlatformManager.instance.analytics.speechProfileContinued();
                _goTo(kCompletePage);
              },
              onEnrolled: _voiceEnrolled,
            )
          : const SizedBox.shrink(),
      OnboardingCompleteScreen(
        onComplete: () {
          SharedPreferencesUtil().saveBool(WelcomeNoteTile.preferenceKey, true);
          SharedPreferencesUtil().onboardingCompleted = true;
          SharedPreferencesUtil().permissionsCompleted = true;
          SharedPreferencesUtil().remove(_resumeKey);
          _completeOnboardingTelemetry();
          updateUserOnboardingState(completed: true);
          PlatformManager.instance.analytics.onboardingCompleted();
          PaintingBinding.instance.imageCache.clear();
          // "Omi is listening now": the phone path starts listening with this phone, as the pendant
          // already does.
          if (!_wearable) _startPhoneListening();
          routeToPage(context, const HomePageWrapper(), replace: true);
        },
      ),
    ];

    final previous = _previousStep;

    return PopScope(
      // System back and the iOS swipe step back one step, like the on-screen back button. On the
      // first step (and Auth / consent) back leaves onboarding as usual.
      canPop: previous == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: OmiColors.surface0,
          body: OnboardingConnectionMonitor(
            showBanner: index != kScanPage && index != kBluetoothPage,
            child: Stack(
              children: [
                // v2: steps sit on the plain midnight page; Welcome and Complete draw the pendant.
                // Page component (no transition for content)
                pages[index],
                // v3 `.obtop`: 7 pt under the status bar, the 50 pt glass back circle (v8.16), then the
                // step bars on its centre line.
                if (barIndex(index) != null || showsBack(index))
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 7, OmiSize.screenMargin, 0),
                      child: Row(
                        children: [
                          // Back on every step (its room kept where it hides); on the first (consent)
                          // it signs out to Welcome.
                          Visibility(
                            visible: showsBack(index),
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: OmiRingButton.glass(
                              key: const Key('onboarding_back'),
                              glyph: OmiGlyphs.back,
                              label: MaterialLocalizations.of(context).backButtonTooltip,
                              onPressed: index == kAiConsentPage
                                  ? () {
                                      OmiHaptics.selection();
                                      _useDifferentAccount();
                                    }
                                  : _goBack,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: barIndex(index) == null
                                ? const SizedBox(height: 50)
                                : OnboardingProgressDots(current: barIndex(index)!, total: kBarCount),
                          ),
                          // The bars sit centred: the back ring's room is kept on the right too.
                          const SizedBox(width: 54),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Exposes the counted steps to tests without widening the wrapper's state class.
@visibleForTesting
abstract final class OnboardingProgressStepsForTest {
  /// The steps a return resumes at (after consent): the name, how you record, the voice.
  static List<int> get steps => _OnboardingWrapperState.kProgressSteps;

  /// The progress bars: consent, then each resumable step.
  static int get barCount => _OnboardingWrapperState.kBarCount;

  static int? barIndex(int page) => _OnboardingWrapperState.barIndex(page);

  static bool showsBack(int page) => _OnboardingWrapperState.showsBack(page);
}

/// The first-run progress (v2): one short bar per real step, filled up to the current one, with a
/// spoken "Step N of M".
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({super.key, required this.current, required this.total});

  /// Zero-based position of the current step.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final motion = OmiMotion.of(context);
    // v3 `.obbar`: one 3 pt segment per step, 4 pt apart, filling the row; done ones in ink.
    return Semantics(
      label: context.l10n.onboardingStepOf(current + 1, total),
      excludeSemantics: true,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: motion.standard,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= current ? OmiColors.textPrimary : OmiColors.outline,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

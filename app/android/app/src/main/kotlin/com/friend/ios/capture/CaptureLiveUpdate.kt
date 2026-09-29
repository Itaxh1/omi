package com.friend.ios.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.friend.ios.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The recording outside the app, Android's counterpart of the iOS Live Activity: while Omi records,
 * the capture notification becomes a Live Update (Android 16's promoted ongoing notification). The
 * status bar shows a chip with the running time, and the notification (on the lock screen too) says
 * what is listening, keeps the clock, and has Pause/Resume and Stop. Before Android 16 it is the same
 * ongoing notification without the chip.
 *
 * Dart (`AndroidLiveUpdateBridge`) publishes the capture state with its words already in the app's
 * language and takes the button taps back, over [CHANNEL_NAME]; it never owns audio here. The
 * foreground services that keep capture alive host this notification in place of their own while a
 * recording from their source is live ([host]), so there is one notification, not two.
 */
object CaptureLiveUpdate {
    const val CHANNEL_NAME = "com.omi.android/liveUpdate"
    private const val TAG = "CaptureLiveUpdate"
    private const val OWN_CHANNEL_ID = "omi_capture_live"
    private const val OWN_NOTIFICATION_ID = 2010
    internal const val ACTION_TAP = "com.friend.ios.capture.LIVE_UPDATE_ACTION"
    internal const val EXTRA_ACTION = "action"
    internal const val EXTRA_RECORDING = "recordingId"
    internal const val EXTRA_REVISION = "conversationRevision"

    /** Notification.EXTRA_REQUEST_PROMOTED_ONGOING (API 36.1); older systems ignore it. */
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    data class State(
        val recordingId: String,
        val revision: Int,
        /** listening, recording, paused, interrupted, connecting or reconnecting. */
        val status: String,
        /** phone or pendant: the service whose notification this replaces. */
        val source: String,
        val startedAtMs: Long,
        val paused: Boolean,
        val canPause: Boolean,
        val canFinish: Boolean,
        val busy: Boolean,
        val title: String,
        val text: String,
        val pauseLabel: String,
        val resumeLabel: String,
        val stopLabel: String,
        /** The status bar chip's words while the clock is stopped ("Paused"); null shows the clock. */
        val chip: String?,
        val channelName: String,
    )

    /** A foreground service whose own notification this replaces while its source records. */
    private class Host(val notificationId: Int, val channelId: String, val fallback: () -> Notification)

    private val hosts = mutableMapOf<String, Host>()
    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var owner: String? = null

    @Volatile
    private var state: State? = null

    /** Called from MainActivity.configureFlutterEngine: Dart can publish from now on. */
    fun attach(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        val methods = MethodChannel(messenger, CHANNEL_NAME)
        channel = methods
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    owner = call.arguments as? String
                    result.success(null)
                }
                "publish" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null && args["ownerId"] == owner) publish(parse(args))
                    result.success(null)
                }
                "detach" -> {
                    if (call.arguments == owner) {
                        owner = null
                        publish(null)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The engine is going away: nothing could answer the buttons, so each service shows its own again. */
    fun detachEngine() {
        channel?.setMethodCallHandler(null)
        channel = null
        owner = null
        publish(null)
    }

    /** A foreground service for [source] ("phone" or "pendant") is showing [notificationId]. */
    fun host(context: Context, source: String, notificationId: Int, channelId: String, fallback: () -> Notification) {
        appContext = appContext ?: context.applicationContext
        hosts[source] = Host(notificationId, channelId, fallback)
        val current = state
        if (current != null && current.source == source) publish(current)
    }

    fun unhost(source: String) {
        hosts.remove(source)
        val current = state
        // The service is gone but the recording goes on: it shows on its own.
        if (current != null && current.source == source) publish(current)
    }

    /** The notification a service for [source] shows now: the Live Update while its recording is live. */
    fun notificationFor(context: Context, source: String, channelId: String): Notification? {
        val current = state ?: return null
        if (current.source != source) return null
        return build(context, channelId, current)
    }

    private fun parse(args: Map<*, *>): State? {
        if (args["active"] != true || args["enabled"] == false) return null
        val labels = args["labels"] as? Map<*, *> ?: return null
        val recordingId = args["recordingId"] as? String ?: return null
        if (recordingId.isEmpty()) return null
        return State(
            recordingId = recordingId,
            revision = (args["conversationRevision"] as? Number)?.toInt() ?: 0,
            status = args["status"] as? String ?: "listening",
            source = args["source"] as? String ?: "pendant",
            startedAtMs = (((args["startedAt"] as? Number)?.toDouble() ?: 0.0) * 1000).toLong(),
            paused = args["paused"] == true,
            canPause = args["canPause"] == true,
            canFinish = args["canFinish"] == true,
            busy = args["busy"] == true,
            title = labels["title"] as? String ?: "Omi",
            text = labels["text"] as? String ?: "",
            pauseLabel = labels["pause"] as? String ?: "Pause",
            resumeLabel = labels["resume"] as? String ?: "Resume",
            stopLabel = labels["stop"] as? String ?: "Stop",
            chip = labels["chip"] as? String,
            channelName = labels["channel"] as? String ?: "Omi",
        )
    }

    private fun publish(next: State?) {
        val context = appContext ?: return
        val previous = state
        state = next
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            // A source that stopped recording gets its service's own notification back (or ours goes).
            if (previous != null && (next == null || next.source != previous.source)) restore(manager, previous.source)
            if (next == null) return
            val host = hosts[next.source]
            if (host != null) {
                manager.cancel(OWN_NOTIFICATION_ID)
                manager.notify(host.notificationId, build(context, host.channelId, next))
            } else {
                ensureOwnChannel(manager, next.channelName)
                manager.notify(OWN_NOTIFICATION_ID, build(context, OWN_CHANNEL_ID, next))
            }
        } catch (e: Exception) {
            // Missing notification permission or a revoked channel: the recording itself goes on.
            Log.w(TAG, "Live Update not shown: ${e.message}")
        }
    }

    private fun restore(manager: NotificationManager, source: String) {
        val host = hosts[source]
        if (host != null) manager.notify(host.notificationId, host.fallback()) else manager.cancel(OWN_NOTIFICATION_ID)
    }

    private fun ensureOwnChannel(manager: NotificationManager, name: String) {
        if (manager.getNotificationChannel(OWN_CHANNEL_ID)?.name == name) return
        manager.createNotificationChannel(
            NotificationChannel(OWN_CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) }
        )
    }

    private fun build(context: Context, channelId: String, s: State): Notification {
        val paused = s.status == "paused"
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_omi)
            .setContentTitle(s.title)
            .setContentText(s.text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            // The lock screen shows it in full: it says only what is listening, never what was said.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openIntent(context, s))
        if (s.paused || s.startedAtMs <= 0) {
            builder.setShowWhen(false)
        } else {
            // The clock counts on its own, here and in the status bar chip.
            builder.setWhen(s.startedAtMs).setShowWhen(true).setUsesChronometer(true)
        }
        if (s.canPause && !s.busy) {
            builder.addAction(0, if (paused) s.resumeLabel else s.pauseLabel, actionIntent(context, s, if (paused) "resume" else "pause"))
        }
        if (s.canFinish && !s.busy) builder.addAction(0, s.stopLabel, actionIntent(context, s, "finish"))
        builder.addExtras(Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })
        val notification = builder.build()
        val chip = s.chip
        if (chip == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return notification
        return Notification.Builder.recoverBuilder(context, notification).setShortCriticalText(chip).build()
    }

    /** Opens Your Omi: `omi://app/capture` goes through the app links Home already routes. */
    private fun openIntent(context: Context, s: State): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.action = Intent.ACTION_VIEW
        launch.data = Uri.parse("omi://app/capture?recording=${Uri.encode(s.recordingId)}")
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun actionIntent(context: Context, s: State, action: String): PendingIntent {
        val intent = Intent(context, CaptureLiveUpdateReceiver::class.java)
            .setAction(ACTION_TAP)
            .putExtra(EXTRA_ACTION, action)
            .putExtra(EXTRA_RECORDING, s.recordingId)
            .putExtra(EXTRA_REVISION, s.revision)
        return PendingIntent.getBroadcast(
            context, action.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    /** A button on the notification: Dart checks it still targets this recording and acts. */
    internal fun dispatch(context: Context, action: String, recordingId: String, revision: Int) {
        main.post {
            val methods = channel
            if (methods == null || owner == null) {
                // Nobody to act: open Omi instead, where the reader can.
                state?.let { s -> openIntent(context, s)?.let { runCatching { it.send() } } }
                return@post
            }
            methods.invokeMethod(
                "action",
                mapOf("action" to action, "recordingId" to recordingId, "conversationRevision" to revision),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {}

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.w(TAG, "Live Update action $action refused: $message")
                    }

                    override fun notImplemented() {}
                },
            )
        }
    }
}

/** Receives the notification's Pause, Resume and Stop taps (not exported: only our own PendingIntents). */
class CaptureLiveUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CaptureLiveUpdate.ACTION_TAP) return
        val action = intent.getStringExtra(CaptureLiveUpdate.EXTRA_ACTION) ?: return
        val recordingId = intent.getStringExtra(CaptureLiveUpdate.EXTRA_RECORDING) ?: return
        val revision = intent.getIntExtra(CaptureLiveUpdate.EXTRA_REVISION, 0)
        CaptureLiveUpdate.dispatch(context, action, recordingId, revision)
    }
}

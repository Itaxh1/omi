package com.pravera.flutter_foreground_task.service

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.wifi.WifiManager
import android.os.*
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.RequestCode
import com.pravera.flutter_foreground_task.models.*
import com.pravera.flutter_foreground_task.utils.*
import com.pravera.flutter_foreground_task.PreferencesKey as PrefsKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * A service class for implementing foreground service.
 *
 * @author Dev-hwang
 * @version 1.0
 */
class ForegroundService : Service() {
    companion object {
        private val TAG = ForegroundService::class.java.simpleName

        private const val ACTION_NOTIFICATION_PRESSED = "onNotificationPressed"
        private const val ACTION_NOTIFICATION_DISMISSED = "onNotificationDismissed"
        private const val ACTION_NOTIFICATION_BUTTON_PRESSED = "onNotificationButtonPressed"
        private const val ACTION_RECEIVE_DATA = "onReceiveData"
        private const val INTENT_DATA_NAME = "intentData"

        private val _isRunningServiceState = MutableStateFlow(false)
        val isRunningServiceState = _isRunningServiceState.asStateFlow()

        private var task: ForegroundTask? = null
        private var taskLifecycleListeners = ForegroundTaskLifecycleListeners()

        fun addTaskLifecycleListener(listener: FlutterForegroundTaskLifecycleListener) {
            taskLifecycleListeners.addListener(listener)
        }

        fun removeTaskLifecycleListener(listener: FlutterForegroundTaskLifecycleListener) {
            taskLifecycleListeners.removeListener(listener)
        }

        fun handleNotificationContentIntent(intent: Intent?) {
            if (intent == null) return

            try {
                // Check if the given intent is a LaunchIntent.
                val isLaunchIntent = (intent.action == Intent.ACTION_MAIN) &&
                        (intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true)
                if (!isLaunchIntent) return

                val data = intent.getStringExtra(INTENT_DATA_NAME)
                if (data == ACTION_NOTIFICATION_PRESSED) {
                    task?.invokeMethod(data, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, e.message, e)
            }
        }

        fun sendData(data: Any?) {
            if (isRunningServiceState.value) {
                task?.invokeMethod(ACTION_RECEIVE_DATA, data)
            }
        }
    }

    private lateinit var foregroundServiceStatus: ForegroundServiceStatus
    private lateinit var foregroundServiceTypes: ForegroundServiceTypes
    private lateinit var foregroundTaskOptions: ForegroundTaskOptions
    private lateinit var foregroundTaskData: ForegroundTaskData
    private lateinit var notificationOptions: NotificationOptions
    private lateinit var notificationContent: NotificationContent
    private var prevForegroundTaskOptions: ForegroundTaskOptions? = null
    private var prevForegroundTaskData: ForegroundTaskData? = null
    private var prevNotificationOptions: NotificationOptions? = null
    private var prevNotificationContent: NotificationContent? = null

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var isTimeout: Boolean = false
    // OMI_FGS_STOP_START_ID: preserve a newer start while an older one stops.
    private var lastDeliveredStartId: Int = 0

    // A broadcast receiver that handles intents that occur in the foreground service.
    private var broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return

            try {
                // This intent has not sent from the current package.
                val iPackageName = intent.`package`
                val cPackageName = packageName
                if (iPackageName != cPackageName) {
                    Log.d(TAG, "This intent has not sent from the current package. ($iPackageName != $cPackageName)")
                    return
                }

                val action = intent.action ?: return
                val data = intent.getStringExtra(INTENT_DATA_NAME)
                task?.invokeMethod(action, data)
            } catch (e: Exception) {
                Log.e(TAG, e.message, e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        // OMI_FGS_EARLY_PROMOTION: no preferences, task, or Dart engine needed.
        promoteColdStart()
        registerBroadcastReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // OMI_FGS_RESTART_PROMOTION: startForegroundService can target an
        // existing instance, so onCreate will not run for this deadline.
        promoteColdStart()
        lastDeliveredStartId = startId
        isTimeout = false
        loadDataFromPreferences()

        val prefs = getSharedPreferences(PrefsKey.FOREGROUND_TASK_OPTIONS_PREFS, Context.MODE_PRIVATE)
        if (prefs.contains(PrefsKey.STOP_WITH_TASK) && prefs.getBoolean(PrefsKey.STOP_WITH_TASK, false)) {
            (application as? Application)?.let {
                TrackVisibilityUtils.install(it) {
                    stopForegroundService()
                }
            }
        }

        var action = foregroundServiceStatus.action
        val isSetStopWithTaskFlag = ForegroundServiceUtils.isSetStopWithTaskFlag(this)

        if (action == ForegroundServiceAction.API_STOP) {
            // OMI_FGS_START_CONTRACT: restart() calls startForegroundService()
            // again. If this stop wins, Android 14+ still crashes unless
            // startForeground() has succeeded.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    createNotificationChannel()
                }
                val serviceId = notificationOptions.serviceId
                val notification = try {
                    createNotification()
                } catch (e: Exception) {
                    Log.e(TAG, "createNotification", e)
                    fallbackContractNotification()
                }
                promoteForeground(serviceId, notification, allowRequestedType = false)
            } catch (e: Exception) {
                Log.e(TAG, "stop-path startForeground contract failed", e)
            }
            stopForegroundService()
            return START_NOT_STICKY
        }

        try {
            if (intent == null) {
                ForegroundServiceStatus.setData(this, ForegroundServiceAction.RESTART)
                foregroundServiceStatus = ForegroundServiceStatus.getData(this)
                action = foregroundServiceStatus.action
            }

            when (action) {
                ForegroundServiceAction.API_START,
                ForegroundServiceAction.API_RESTART -> {
                    startForegroundService()
                    createForegroundTask()
                }
                ForegroundServiceAction.API_UPDATE -> {
                    // onStartCommand first used shortService even for updates.
                    // Restore the long-running location type before continuing.
                    startForegroundService()
                    updateNotification()
                    val prevCallbackHandle = prevForegroundTaskData?.callbackHandle
                    val currCallbackHandle = foregroundTaskData.callbackHandle
                    if (prevCallbackHandle != currCallbackHandle) {
                        createForegroundTask()
                    } else {
                        val prevEventAction = prevForegroundTaskOptions?.eventAction
                        val currEventAction = foregroundTaskOptions.eventAction
                        if (prevEventAction != currEventAction) {
                            updateForegroundTask()
                        }
                    }
                }
                ForegroundServiceAction.REBOOT,
                ForegroundServiceAction.RESTART -> {
                    startForegroundService()
                    createForegroundTask()
                    Log.d(TAG, "The service has been restarted by Android OS.")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, e.message, e)
            stopForegroundService()
        }

        return if (isSetStopWithTaskFlag) {
            START_NOT_STICKY
        } else {
            START_STICKY
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        val isTimeout = this.isTimeout
        destroyForegroundTask(isTimeout)
        stopForegroundService()
        unregisterBroadcastReceiver()

        var isCorrectlyStopped = false
        if (::foregroundServiceStatus.isInitialized) {
            isCorrectlyStopped = foregroundServiceStatus.isCorrectlyStopped()
        }

        // Safely handle auto-restart by checking if options are initialized.
        if (::foregroundTaskOptions.isInitialized) {
            val allowAutoRestart = foregroundTaskOptions.allowAutoRestart
            if (allowAutoRestart && !isCorrectlyStopped && !ForegroundServiceUtils.isSetStopWithTaskFlag(this)) {
                Log.e(TAG, "The service will be restarted after 5 seconds because it wasn't properly stopped.")
                RestartReceiver.setRestartAlarm(this, 5000)
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // A new start may be pending when stopWithTask removes the task.
        promoteColdStart()
        super.onTaskRemoved(rootIntent)
        if (ForegroundServiceUtils.isSetStopWithTaskFlag(this)) {
            stopSelf()
        } else {
            RestartReceiver.setRestartAlarm(this, 1000)
        }
    }

    override fun onTimeout(startId: Int) {
        super.onTimeout(startId)
        isTimeout = true
        stopForegroundService()
        Log.e(TAG, "The service(id: $startId) timed out and was terminated by the system.")
    }

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int, fgsType: Int) {
        super.onTimeout(startId, fgsType)
        isTimeout = true
        stopForegroundService()
        Log.e(TAG, "The service(id: $startId) timed out and was terminated by the system.")
    }

    private fun loadDataFromPreferences() {
        foregroundServiceStatus = ForegroundServiceStatus.getData(applicationContext)
        foregroundServiceTypes = ForegroundServiceTypes.getData(applicationContext)
        if (::foregroundTaskOptions.isInitialized) { prevForegroundTaskOptions = foregroundTaskOptions }
        foregroundTaskOptions = ForegroundTaskOptions.getData(applicationContext)
        if (::foregroundTaskData.isInitialized) { prevForegroundTaskData = foregroundTaskData }
        foregroundTaskData = ForegroundTaskData.getData(applicationContext)
        if (::notificationOptions.isInitialized) { prevNotificationOptions = notificationOptions }
        notificationOptions = NotificationOptions.getData(applicationContext)
        if (::notificationContent.isInitialized) { prevNotificationContent = notificationContent }
        notificationContent = NotificationContent.getData(applicationContext)
    }

    private fun registerBroadcastReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(ACTION_NOTIFICATION_BUTTON_PRESSED)
            addAction(ACTION_NOTIFICATION_PRESSED)
            addAction(ACTION_NOTIFICATION_DISMISSED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(broadcastReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(broadcastReceiver, intentFilter)
        }
    }

    private fun unregisterBroadcastReceiver() {
        unregisterReceiver(broadcastReceiver)
    }


    // OMI_FGS_START_CONTRACT
    @SuppressLint("WrongConstant", "InlinedApi")
    private fun promoteForeground(
        serviceId: Int,
        notification: Notification,
        allowRequestedType: Boolean
    ): Boolean {
        if (allowRequestedType) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    var type = foregroundServiceTypes.value
                    // MANIFEST (-1) would also adopt shortService from the
                    // manifest and put the 3-minute shortService limit on the
                    // long-running location task. This service is location.
                    if (type <= 0) {
                        type = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                    }
                    startForeground(serviceId, notification, type)
                } else {
                    startForeground(serviceId, notification)
                }
                return true
            } catch (e: Exception) {
                Log.e(TAG, "startForeground rejected", e)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                startForeground(
                    serviceId,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
                )
            } catch (e: Exception) {
                Log.e(TAG, "shortService startForeground failed", e)
            }
        }
        return false
    }

    private fun fallbackContractNotification(): Notification {
        val channelId = "foreground_service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "Foreground Service", NotificationManager.IMPORTANCE_LOW)
                )
            }
            return Notification.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("Omi")
                .setOngoing(true)
                .build()
        }
        @Suppress("DEPRECATION")
        return Notification()
    }

    // The fallback channel and icon are native constants. On Android 14+ the
    // shortService type has no while-in-use location prerequisite. The normal
    // promotion below replaces it with location when that type is allowed;
    // otherwise the service stops before the shortService timeout.
    private fun promoteColdStart() {
        try {
            val notification = fallbackContractNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    1000,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
                )
            } else {
                startForeground(1000, notification)
            }
            Log.i(TAG, "OMI_FGS_EARLY_PROMOTION: startForeground succeeded in onCreate")
        } catch (e: Exception) {
            Log.e(TAG, "OMI_FGS_EARLY_PROMOTION: startForeground failed", e)
            throw IllegalStateException("cold-start foreground promotion failed", e)
        }
    }

    @SuppressLint("WrongConstant", "SuspiciousIndentation")
    private fun startForegroundService() {
        RestartReceiver.cancelRestartAlarm(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel()
        }

        val serviceId = notificationOptions.serviceId
        val notification = try {
            createNotification()
        } catch (e: Exception) {
            Log.e(TAG, "createNotification", e)
            fallbackContractNotification()
        }
        // OMI_FGS_START_CONTRACT: a rejected type still calls startForeground
        // (shortService) before this throws, so the outer catch can stop
        // without leaving the timeout armed.
        if (!promoteForeground(serviceId, notification, allowRequestedType = true)) {
            throw IllegalStateException("foreground type rejected after satisfying start contract")
        }

        releaseLockMode()
        acquireLockMode()

        _isRunningServiceState.update { true }
    }

    private fun stopForegroundService() {
        // A visibility callback can stop this existing instance before its
        // queued start command runs. Promote before removing foreground state.
        promoteColdStart()
        RestartReceiver.cancelRestartAlarm(this)

        releaseLockMode()
        stopForeground(true)
        // OMI_FGS_STOP_START_ID: an unconditional stopSelf() tears down the
        // ServiceRecord even when startForegroundService has a newer pending
        // command. Android can then time out that new foreground start.
        stopSelf(lastDeliveredStartId)

        _isRunningServiceState.update { false }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel() {
        val channelId = notificationOptions.channelId
        val channelName = notificationOptions.channelName
        val channelDesc = notificationOptions.channelDescription
        val channelImportance = notificationOptions.channelImportance

        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(channelId) == null) {
            val channel = NotificationChannel(channelId, channelName, channelImportance).apply {
                if (channelDesc != null) {
                    description = channelDesc
                }
                enableVibration(notificationOptions.enableVibration)
                if (!notificationOptions.playSound) {
                    setSound(null, null)
                }
                setShowBadge(notificationOptions.showBadge)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        // notification icon
        val icon = notificationContent.icon
        val iconResId = getIconResId(icon)
        val iconBackgroundColor = icon?.backgroundColorRgb?.let(::getRgbColor)

        // notification intent
        val contentIntent = getContentIntent()
        val deleteIntent = getDeleteIntent()

        // notification actions
        var needsRebuildButtons = false
        val prevButtons = prevNotificationContent?.buttons
        val currButtons = notificationContent.buttons
        if (prevButtons != null) {
            if (prevButtons.size != currButtons.size) {
                needsRebuildButtons = true
            } else {
                for (i in currButtons.indices) {
                    if (prevButtons[i] != currButtons[i]) {
                        needsRebuildButtons = true
                        break
                    }
                }
            }
        } else {
            needsRebuildButtons = true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = Notification.Builder(this, notificationOptions.channelId)
            builder.setOngoing(true)
            builder.setShowWhen(notificationOptions.showWhen)
            builder.setSmallIcon(iconResId)
            builder.setContentIntent(contentIntent)
            builder.setContentTitle(notificationContent.title)
            builder.setContentText(notificationContent.text)
            builder.style = Notification.BigTextStyle()
            builder.setVisibility(notificationOptions.visibility)
            builder.setOnlyAlertOnce(notificationOptions.onlyAlertOnce)
            if (iconBackgroundColor != null) {
                builder.setColor(iconBackgroundColor)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                builder.setDeleteIntent(deleteIntent)
            }

            val actions = buildNotificationActions(currButtons, needsRebuildButtons)
            for (action in actions) {
                builder.addAction(action)
            }

            return builder.build()
        } else {
            val builder = NotificationCompat.Builder(this, notificationOptions.channelId)
            builder.setOngoing(true)
            builder.setShowWhen(notificationOptions.showWhen)
            builder.setSmallIcon(iconResId)
            builder.setContentIntent(contentIntent)
            builder.setContentTitle(notificationContent.title)
            builder.setContentText(notificationContent.text)
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(notificationContent.text))
            builder.setVisibility(notificationOptions.visibility)
            builder.setOnlyAlertOnce(notificationOptions.onlyAlertOnce)
            if (iconBackgroundColor != null) {
                builder.color = iconBackgroundColor
            }
            if (!notificationOptions.enableVibration) {
                builder.setVibrate(longArrayOf(0L))
            }
            if (!notificationOptions.playSound) {
                builder.setSound(null)
            }
            builder.priority = notificationOptions.priority

            val actions = buildNotificationCompatActions(currButtons, needsRebuildButtons)
            for (action in actions) {
                builder.addAction(action)
            }

            return builder.build()
        }
    }

    private fun updateNotification() {
        val serviceId = notificationOptions.serviceId
        val notification = createNotification()
        val nm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getSystemService(NotificationManager::class.java)
        } else {
            // crash 23+
            ContextCompat.getSystemService(this, NotificationManager::class.java)
        }
        nm?.notify(serviceId, notification)
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireLockMode() {
        if (foregroundTaskOptions.allowWakeLock && (wakeLock == null || wakeLock?.isHeld == false)) {
            wakeLock =
                (applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager).run {
                    newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ForegroundService:WakeLock").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                }
        }

        if (foregroundTaskOptions.allowWifiLock && (wifiLock == null || wifiLock?.isHeld == false)) {
            wifiLock =
                (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).run {
                    createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ForegroundService:WifiLock").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                }
        }
    }

    private fun releaseLockMode() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                wakeLock = null
            }
        }

        wifiLock?.let {
            if (it.isHeld) {
                it.release()
                wifiLock = null
            }
        }
    }

    private fun createForegroundTask() {
        destroyForegroundTask()

        task = ForegroundTask(
            context = this,
            serviceStatus = foregroundServiceStatus,
            taskData = foregroundTaskData,
            taskEventAction = foregroundTaskOptions.eventAction,
            taskLifecycleListener = taskLifecycleListeners
        )
    }

    private fun updateForegroundTask() {
        task?.update(taskEventAction = foregroundTaskOptions.eventAction)
    }

    private fun destroyForegroundTask(isTimeout: Boolean = false) {
        task?.destroy(isTimeout)
        task = null
    }

    private fun getIconResId(icon: NotificationIcon?): Int {
        try {
            val packageManager = applicationContext.packageManager
            val packageName = applicationContext.packageName
            val appInfo = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)

            // application icon
            if (icon == null) {
                return appInfo.icon
            }

            // custom icon
            val metaData = appInfo.metaData
            if (metaData != null) {
                return metaData.getInt(icon.metaDataName)
            }

            return 0
        } catch (e: Exception) {
            Log.e(TAG, "getIconResId($icon)", e)
            return 0
        }
    }

    private fun getContentIntent(): PendingIntent {
        val packageManager = applicationContext.packageManager
        val packageName = applicationContext.packageName
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            putExtra(INTENT_DATA_NAME, ACTION_NOTIFICATION_PRESSED)

            // set initialRoute
            val initialRoute = notificationContent.initialRoute
            if (initialRoute != null) {
                putExtra("route", initialRoute)
            }
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }

        return PendingIntent.getActivity(this, RequestCode.NOTIFICATION_PRESSED, intent, flags)
    }

    private fun getDeleteIntent(): PendingIntent {
        val intent = Intent(ACTION_NOTIFICATION_DISMISSED).apply {
            setPackage(packageName)
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }

        return PendingIntent.getBroadcast(this, RequestCode.NOTIFICATION_DISMISSED, intent, flags)
    }

    private fun getRgbColor(rgb: String): Int? {
        val rgbSet = rgb.split(",")
        return if (rgbSet.size == 3) {
            Color.rgb(rgbSet[0].toInt(), rgbSet[1].toInt(), rgbSet[2].toInt())
        } else {
            null
        }
    }

    private fun getTextSpan(text: String, color: Int?): Spannable {
        return if (color != null) {
            SpannableString(text).apply {
                setSpan(ForegroundColorSpan(color), 0, length, 0)
            }
        } else {
            SpannableString(text)
        }
    }

    private fun buildNotificationActions(
        buttons: List<NotificationButton>,
        needsRebuild: Boolean = false
    ): List<Notification.Action> {
        val actions = mutableListOf<Notification.Action>()
        for (i in buttons.indices) {
            val intent = Intent(ACTION_NOTIFICATION_BUTTON_PRESSED).apply {
                setPackage(packageName)
                putExtra(INTENT_DATA_NAME, buttons[i].id)
            }
            var flags = PendingIntent.FLAG_IMMUTABLE
            if (needsRebuild) {
                flags = flags or PendingIntent.FLAG_CANCEL_CURRENT
            }
            val textColor = buttons[i].textColorRgb?.let(::getRgbColor)
            val text = getTextSpan(buttons[i].text, textColor)
            val pendingIntent =
                PendingIntent.getBroadcast(this, i + 1, intent, flags)
            val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Notification.Action.Builder(null, text, pendingIntent).build()
            } else {
                Notification.Action.Builder(0, text, pendingIntent).build()
            }
            actions.add(action)
        }

        return actions
    }

    private fun buildNotificationCompatActions(
        buttons: List<NotificationButton>,
        needsRebuild: Boolean = false
    ): List<NotificationCompat.Action> {
        val actions = mutableListOf<NotificationCompat.Action>()
        for (i in buttons.indices) {
            val intent = Intent(ACTION_NOTIFICATION_BUTTON_PRESSED).apply {
                setPackage(packageName)
                putExtra(INTENT_DATA_NAME, buttons[i].id)
            }
            var flags = PendingIntent.FLAG_IMMUTABLE
            if (needsRebuild) {
                flags = flags or PendingIntent.FLAG_CANCEL_CURRENT
            }
            val textColor = buttons[i].textColorRgb?.let(::getRgbColor)
            val text = getTextSpan(buttons[i].text, textColor)
            val pendingIntent =
                PendingIntent.getBroadcast(this, i + 1, intent, flags)
            val action = NotificationCompat.Action.Builder(0, text, pendingIntent).build()
            actions.add(action)
        }

        return actions
    }
}

package app.vynody.player

import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val MEDIA_OBSERVER_CHANNEL = "app.vynody.player/media_observer"
    private val BATTERY_CHANNEL = "app.vynody.player/battery"
    private var eventSink: EventChannel.EventSink? = null
    private var contentObserver: ContentObserver? = null

//    init {
//        System.loadLibrary("audio_core")
//    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_OBSERVER_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerMediaObserver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterMediaObserver()
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBatterySettings" -> {
                        try {
                            val intent = Intent().apply {
                                action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent().apply {
                                action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openAppSettings" -> {
                        try {
                            val intent = Intent().apply {
                                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerMediaObserver() {
        if (contentObserver != null) return

        val handler = Handler(Looper.getMainLooper())
        contentObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                // Avoid flooding with multiple changes in short time
                handler.removeCallbacksAndMessages(null)
                handler.postDelayed({
                    eventSink?.success("media_changed")
                }, 1000)
            }
        }

        try {
            contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                true,
                contentObserver!!
            )
        } catch (e: Exception) {
            // Log error or notify flutter if needed
        }
    }

    private fun unregisterMediaObserver() {
        contentObserver?.let {
            contentResolver.unregisterContentObserver(it)
            contentObserver = null
        }
    }

    override fun onDestroy() {
        unregisterMediaObserver()
        super.onDestroy()
    }
}

package app.vynody.player

import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : AudioServiceActivity() {
    private val MEDIA_OBSERVER_CHANNEL = "app.vynody.player/media_observer"
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

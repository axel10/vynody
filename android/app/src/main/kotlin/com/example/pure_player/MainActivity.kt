package com.example.pure_player

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity(){
    init {
        System.loadLibrary("audio_visualizer_player")
    }
}

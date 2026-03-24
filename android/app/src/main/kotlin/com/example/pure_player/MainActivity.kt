package com.example.pure_player

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    init {
        System.loadLibrary("audio_visualizer_player")
    }
}

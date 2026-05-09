package com.example.noti_notes_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PeerServicePlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}

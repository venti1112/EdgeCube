package com.venti1112.edgecube

import com.venti1112.edgecube.localservice.LocalServiceChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LocalServiceChannel.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
    }
}

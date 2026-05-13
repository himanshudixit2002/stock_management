package com.stockmanager.stock_management

import android.graphics.Color
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Explicit SystemBarStyle args so Kotlin emits
        // `invoke-static EdgeToEdge.enable(ComponentActivity, SystemBarStyle, SystemBarStyle)`
        // instead of the synthetic `enable$default` wrapper. Play Console's
        // static analyzer matches the former, not the latter.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
    }
}

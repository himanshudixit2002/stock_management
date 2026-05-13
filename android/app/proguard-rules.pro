## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

## Google Play Core (deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

## Keep androidx.activity EdgeToEdge symbols so Play Console's static analysis detects them
-keep class androidx.activity.EdgeToEdge { *; }
-keep class androidx.activity.EdgeToEdgeKt { *; }
-keep class androidx.activity.SystemBarStyle { *; }
-dontwarn androidx.activity.EdgeToEdge

## Preserve MainActivity.onCreate so the enableEdgeToEdge() call is not inlined/renamed.
## Play Console's static analysis looks for this invocation to clear the
## "Edge-to-edge may not display for all users" warning.
-keep class com.stockmanager.stock_management.MainActivity {
    protected void onCreate(android.os.Bundle);
}

## Disable R8 method inlining/optimization. Shrinking and obfuscation still run.
## Without this, R8 inlines the single enableEdgeToEdge() invocation into
## onCreate's body, so the direct `invokestatic androidx/activity/EdgeToEdge.enable`
## instruction disappears from the APK and Play Console no longer detects it.
-dontoptimize

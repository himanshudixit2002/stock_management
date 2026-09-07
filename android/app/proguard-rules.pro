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

## Keep androidx.activity EdgeToEdge symbols so Play Console's static analysis
## can still resolve them by name after shrinking.
-keep class androidx.activity.EdgeToEdge { *; }
-keep class androidx.activity.EdgeToEdgeKt { *; }
-keep class androidx.activity.SystemBarStyle { *; }
-dontwarn androidx.activity.EdgeToEdge

## Preserve MainActivity.onCreate so the enableEdgeToEdge() call keeps a stable,
## unrenamed home. Note this keeps the METHOD, it does not stop R8 inlining into
## it -- see the note below on why that is no longer something we fight.
-keep class com.stockmanager.stock_management.MainActivity {
    protected void onCreate(android.os.Bundle);
}

## NOTE: this file previously carried a blanket `-dontoptimize` whose stated
## purpose was to stop R8 inlining enableEdgeToEdge() so Play Console's static
## analysis could see the invokestatic. It did not work: the flag shipped from
## 1.0.19+21 onward and Play still reported "Edge-to-edge may not display for
## all users" against release 30 (1.0.26), nine releases later. Meanwhile it
## disabled every R8 optimization, which Play separately flags as a memory and
## performance problem. Optimization is back on; edge-to-edge correctness is
## enforced where it actually matters, in MainActivity and in the Dart inset
## handling, rather than by pattern-matching bytecode.

## flutter_local_notifications: the plugin serialises notification details with
## Gson, which resolves types reflectively. Without these, R8 strips the model
## classes and posting an alert fails at runtime in release only.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.dexterous.**

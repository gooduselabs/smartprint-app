# Plugins that call into Kotlin/Java through JNI (Pigeon JNI / jnigen) are invisible to R8:
# without these rules R8 strips/renames the methods and the Dart side fails at startup with
#   NoSuchMethodError: SharedPreferencesApiRegistrar.getAll(...)
# (shared_preferences_android >= 2.5.0 ships no consumer rules). See lumi v1.2.1 ANR fix.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class dev.flutter.pigeon.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keepclassmembers class * { @androidx.annotation.Keep *; }
# Kotlin types that appear in those JNI method signatures (suspend funs take a Continuation).
# R8 renamed kotlin.coroutines.Continuation -> `lg`, so the JNI lookup of
# getAll(String, List, Continuation) failed even though getAll itself was kept.
# Pigeon JNI also looks up kotlin.Result$Failure, kotlin.Unit, enums… by name at runtime, so keep
# the Kotlin stdlib and coroutines intact (≈+300 KB, worth not shipping another startup crash).
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
# MediaPipe LLM Inference / LiteRT (flutter_gemma) and ML Kit use JNI + protobuf reflection.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class com.google.ai.edge.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-dontwarn com.google.ai.edge.**
-dontwarn com.google.mlkit.vision.text.**
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**

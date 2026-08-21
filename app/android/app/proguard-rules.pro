# --- keep R8 from inlining across Flogger's stack walk --------------------
# MediaPipe's Graph static initializer logs via Google Flogger, which walks the
# call stack to find its caller. R8's method inlining (on by default with
# proguard-android-optimize.txt) collapses those frames, so Flogger throws
# "no caller found on the stack", failing Graph's <clinit>:
#   NoClassDefFoundError: com.google.mediapipe.framework.Graph
# Disabling optimization keeps the frames intact. Shrinking + obfuscation (which
# is what we actually need for the protobuf keeps below) still run.
-dontoptimize

# --- protobuf-lite (the actual bug) ---------------------------------------
# Flutter release builds run R8. MediaPipe Tasks Vision uses
# com.google.protobuf:protobuf-javalite, whose generated message classes read
# their fields *reflectively by name* (e.g. `platform_`). Nothing in MediaPipe's
# or protobuf's consumer rules keeps those fields, so R8 strips them and the
# reflective lookup dies at PoseLandmarker.createFromOptions:
#   java.lang.RuntimeException: Field platform_ for <obf> not found.
# Keep every GeneratedMessageLite subclass's fields so the reflection resolves.
# (DataStore's *shaded* androidx…protobuf already has this rule via its own
# consumer file — it's only com.google.protobuf that was unprotected.)
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# --- MediaPipe Tasks Vision ------------------------------------------------
# Its AAR ships a consumer rule for com.google.mediapipe.**, but keep it
# explicitly too, and preserve JNI entry points the native graph looks up.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**
-keepclasseswithmembernames class * {
    native <methods>;
}

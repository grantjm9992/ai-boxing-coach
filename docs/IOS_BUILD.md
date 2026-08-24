# iOS build & the pose plugin port

The app is Flutter/Dart end-to-end except one native piece: the `pose_landmarker`
plugin. It now has an **iOS implementation** (Swift + MediaPipe Tasks Vision)
alongside the Android Kotlin one, on the same method/event channels, so the
shared Dart layer and the cross-language golden fixtures apply unchanged.

- Plugin: `app/packages/pose_landmarker/ios/`
  (`pose_landmarker.podspec`, `Classes/PoseLandmarkerPlugin.swift`)
- Registered in the plugin pubspec under `flutter.plugin.platforms.ios`.

> ⚠️ **Written but not yet built/validated.** There is no iOS toolchain in the
> dev environment this was authored in. It needs a first build on a Mac with
> Xcode + an iPhone, and the golden-parity check below, before it can be trusted.

## First build

```bash
cd app
flutter pub get
cd ios && pod install            # pulls MediaPipeTasksVision (~0.10.x)
cd ..
open ios/Runner.xcworkspace       # set your Team under Signing & Capabilities
flutter build ios --release       # or run on a device from Xcode
```

Requirements already wired:
- `ios/Podfile` → `platform :ios, '13.0'` (MediaPipe needs 13+).
- `Info.plist` → `NSCameraUsageDescription` and the
  `com.aiboxingcoach.boxing_coach` URL scheme for the Supabase OAuth callback.
- The `.task` model is a Flutter asset already; the shared provisioner copies it
  to a file at runtime, so no iOS-specific model step.

## Validate parity before trusting it (important)

The Android and iOS plugins must emit the **same landmark sequence** for the same
clip, or the rule engine's calibration silently drifts on iOS.

1. Record/analyse the same clip on an Android and an iOS device.
2. Export the pose JSON (review screen → share) from each.
3. Diff with `python scripts/analyse_pose_json.py "<file>"` and compare.

Watch especially for:
- **Orientation** — portrait clips must come out upright. `orientation(for:)`
  maps the track's `preferredTransform`; if iOS poses look rotated/mirrored vs
  Android, that mapping is the first suspect.
- **Coordinate convention** — MediaPipe normalises x/y the same on both, but
  confirm z sign and visibility populate.

## Known gaps / notes

- Decode uses `AVAssetReader` (sequential, like Android's MediaCodec path).
  There's no slow-path fallback yet; if an unusual container fails to read,
  add an `AVAssetImageGenerator` fallback mirroring Android's retriever path.
- iOS debugging is heavier than the Android release-APK workflow — the in-app
  error surfacing (`describe`) is mirrored here so a screenshot still identifies
  a device-only failure.
- Apple sign-in is still deferred; Google sign-in should work once the URL
  scheme above is allow-listed in the Supabase dashboard for iOS.

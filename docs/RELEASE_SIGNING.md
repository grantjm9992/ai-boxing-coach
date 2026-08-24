# Release signing (Google Play)

Play **rejects debug-signed uploads**, so a store build needs a real upload key.
The Gradle config (`app/android/app/build.gradle.kts`) reads
`app/android/key.properties` when it exists and falls back to the debug keys
otherwise, so nothing here breaks local/CI debug builds.

`key.properties`, `*.jks` and `*.keystore` are already gitignored
(`app/android/.gitignore`) — **never commit them**.

## 1. Create the upload keystore (once)

```bash
keytool -genkey -v \
  -keystore ~/aiboxingcoach-upload.jks \
  -keyalias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

It asks for a store password, a key password, and a name/org. **Back this file
and both passwords up somewhere safe** (password manager + offline copy). If you
lose it you can no longer ship updates under the same key without Google's key
reset — treat it like the master key to the app.

> Recommended: also enable **Play App Signing** in the Play Console (it's the
> default for new apps). Google then holds the *app signing key* and this
> keystore is only your *upload key* — which Google can reset if lost. Still
> back it up.

## 2. Create `app/android/key.properties`

```properties
storePassword=<store password from step 1>
keyPassword=<key password from step 1>
keyAlias=upload
storeFile=/Users/grantmacdonald/aiboxingcoach-upload.jks
```

Use an absolute `storeFile` path to avoid ambiguity.

## 3. Build the upload artifact

```bash
cd app
flutter build appbundle --release   # -> build/app/outputs/bundle/release/app-release.aab
```

Upload the `.aab` to the Play Console. (`flutter build apk --release` still works
for your on-device testing; Play wants the `.aab`.)

## Verify it's signed with your key, not debug

```bash
# Debug keystore SHA-1 you want to NOT see:
keytool -list -v -keystore ~/.android/debug.keystore -storepass android | grep SHA1
# Your upload key:
keytool -list -v -keystore ~/aiboxingcoach-upload.jks | grep SHA1
```

They must differ. The build also needs the **Android SDK 36 platform** installed
(`sdkmanager "platforms;android-36"`) because `compileSdk`/`targetSdk` are pinned
to 36 for Play's 2026 requirement.

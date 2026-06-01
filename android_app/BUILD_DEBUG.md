# Building Debug APK

This directory contains the configuration for building debug APKs locally using Docker.

## Quick Start

Build a debug APK:
```bash
docker compose run --rm apk-debug
```

The APK will be output to:
```
android_app/build/app/outputs/flutter-apk/app-debug.apk
```

> **Note**: The `apk-debug` service uses the "tools" profile, so it won't start automatically when you run `docker compose up`. It only runs when explicitly invoked with `docker compose run`.

## Installing on Device

Using ADB:
```bash
adb install android_app/build/app/outputs/flutter-apk/app-debug.apk
```

Or drag-and-drop the APK file onto your Android device.

## Debug vs Release

| Aspect | Debug Build | Release Build |
|--------|-------------|---------------|
| **Application ID** | `com.lingodiary.lingodiary_app.debug` | `com.lingodiary.lingodiary_app` |
| **App Label** | LingoDiary (Debug) | LingoDiary |
| **Version Suffix** | `-DEBUG` (e.g., "5.0.0-DEBUG") | None |
| **Signing** | Auto-generated debug keystore | Release keystore (GHA only) |
| **Coexistence** | ✅ Can install alongside release | N/A |
| **Build Time** | ~5-10 min (first build) | ~10-15 min (GHA) |

The debug APK uses a `.debug` application ID suffix, so it installs as a completely separate app. You can have both debug and release versions on the same device simultaneously.

## Implementation Details

- **Dockerfile**: `Dockerfile.apk-debug` (Java 17 + Flutter 3.41.9 + Android SDK)
- **Build Config**: `android_app/android/app/build.gradle.kts` (debug buildType)
- **App Label**: `android_app/android/app/src/debug/AndroidManifest.xml`

## First Build

The first build downloads ~2GB of dependencies (Flutter SDK, Android SDK, build tools). Subsequent builds are much faster thanks to Docker layer caching.

To rebuild the Docker image:
```bash
docker compose build apk-debug
```

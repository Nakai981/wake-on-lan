# Verification

Environment: Windows, Flutter 3.47.5 / Dart 3.13.4, Android emulator API 37.

- `flutter analyze`: no issues.
- `flutter test`: 11 tests passed (including narrow-screen menu navigation, favorites filtering and delete cancellation).
- `flutter build apk --debug`: successful.
- Installed and launched on emulator-5554; no Flutter/AndroidRuntime crash in the captured log.
- Visually inspected `home-android.png` and `setup-android.png`.
- Wi-Fi plugin returned the emulator subnet 10.0.2.0 successfully.

Tests cover valid/invalid MAC input, 102-byte Magic Packet contents, actual loopback UDP delivery and retry count, non-/24 subnet calculations, persistent device/history data, onboarding/save, invalid MAC blocking, bounded scanner concurrency and cancellation.

Not verified: physical PC wake, physical Android Wi-Fi broadcast routing, iPhone permissions/broadcast, iOS compilation/signing. These require the corresponding hardware and, for iOS, macOS/Xcode and an approved multicast entitlement.

The supplied APK is a debug/testing build, not a store release.


Home refinement: removed discovery shortcuts and promotional copy, compacted the network strip and PC cards, kept a single add-device action, and hid filtering when only one PC exists. Be Vietnam Pro is bundled offline in six weights; its entries were verified in the built FontManifest.json.

Latest APK installed successfully. Visually inspected docs/home-compact.png on the Android emulator: bundled Be Vietnam Pro renders Vietnamese text correctly; compact Home has no visible clipping.

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

Direct Home wake: 13 tests passed, including immediate send notification, duplicate-button disabling, positive response after 10 seconds, and automatic help navigation on no response. Network behavior is mocked for timing/UI tests; physical PC wake still needs hardware verification.

Windows Agent addition:
- .NET Framework Windows tray EXE built using windows-agent/Build.ps1; portable ZIP in dist/WakeMyPcAgent.zip.
- 19 tests passed via windows-agent/Test.ps1, including real Dart-to-C# loopback protocol tests, wrong-key rejection, replay rejection, forged-response rejection, migration, and shutdown confirmation cancellation.
- flutter analyze: no issues. Android debug APK built successfully.
- No live shutdown or Sleep executed. Test server uses a separate loopback-only handler returning simulated; startup registry and Firewall were not changed during development.
- Windows tray visual layout and real power transitions still require manual validation; iOS still requires macOS build/signing and hardware testing.

Minimal selected-PC Home redesign:
- flutter analyze: no issues. flutter test: 18 tests passed (without optional live-agent protocol suite).
- Verified unique star selection, only selected PC on Home, confirmed online/light vs unresponsive/black states, preserved delayed wake check and shutdown confirmation.
- Added foreground 15-second status refresh; last confirmed online state is retained while checking to avoid flashing black.
- Rendered and visually reviewed docs/home-dark.png, docs/home-light.png and docs/device-list.png with bundled font/icons; mock device/status used only by preview harness.
- APK built and installed on Android emulator. No real power command executed.

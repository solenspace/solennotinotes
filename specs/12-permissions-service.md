# 12 — permissions-service

## Goal

Wrap the `permission_handler` plugin in a typed `PermissionsService` abstraction so feature code never imports the plugin directly. The service exposes one method per permission Notinotes will ever need (mic, camera, photos, notifications, BLE / Nearby), each returning a typed `PermissionResult` enum. A small `PermissionExplainerSheet` widget surfaces denial state and deep-links to the OS settings when a permission is permanently denied. Per [architecture.md](../context/architecture.md) invariant 9, every request is **point-of-use**: the service is the only thing that calls `Permission.x.request()`, and consumers always resolve the result before performing the gated action. After this spec, no widget, screen, BLoC, or repository under `lib/` imports `package:permission_handler` directly.

This is a foundational plumbing spec — Specs 13 (audio capture), 22 (P2P transport), and existing notification flows all consume it. **No permission is requested by this spec itself**; we just make the service available.

## Dependencies

- [03-project-structure-migration](03-project-structure-migration.md) — `lib/services/` is the cross-cutting service root.
- [10-theme-tokens](10-theme-tokens.md) — the explainer sheet uses `context.tokens.*`.

## Agents & skills

**Pre-coding skills:**
- `dart-flutter-patterns` — abstract-service + concrete impl + fake test double pattern.

**After-coding agents:**
- `flutter-expert` — verify Info.plist + AndroidManifest changes don't leak into release builds incorrectly; tools-namespace flags work.
- `code-reviewer` — confirm no consumer imports `package:permission_handler` directly; the wrapper is the sole gate.

## Design Decisions

- **Instance class via `RepositoryProvider`.** Matches the rest of the codebase (`NotesRepository`, `NotiIdentityRepository`, …). Testable: BLoCs and services receive a `PermissionsService` constructor arg; tests pass a `FakePermissionsService`. Static-class style is rejected because it can't be mocked without code under test reaching into a global mutable.
- **Typed result enum, no throws.** `PermissionResult.{granted, denied, permanentlyDenied, restricted, limited}` mirrors the underlying plugin's status enum but in our own namespace. Callers `switch` on it; no exception-driven control flow. The "limited" variant matters on iOS 14+ for photo-picker partial-access; we plumb it through.
- **One method per permission.** `requestMicrophone()`, `requestCamera()`, `requestPhotos()`, `requestNotifications()`, `requestBluetoothScan()`, `requestBluetoothConnect()`, `requestBluetoothAdvertise()`, `requestNearbyWifiDevices()`. Per-permission methods make grep-finding gated entry points trivial; a single generic `request(Permission)` would lose type safety and let consumers pass arbitrary permissions, including ones we explicitly never use (`location`, `contacts`, `calendar`).
- **`status*` getters that don't request.** Each permission gets a sibling `microphoneStatus()` / `cameraStatus()` / etc. that returns the current `PermissionResult` without prompting. UI uses these to render explanations or hide affordances; only the actual feature dispatch calls the `request*` variant.
- **Native manifest entries are part of this spec.** The implementer adds the iOS `Info.plist` keys and the Android `AndroidManifest.xml` `<uses-permission>` declarations for every permission method scaffolded here. **Permissions are not requested at runtime by this spec**, but the manifests must declare them or `permission_handler` returns `permanentlyDenied` immediately on platforms that gate by manifest. This is the reason permissions land in *this* spec rather than as scattered additions in 13/22 — manifest churn lives in one place.
- **`PermissionExplainerSheet` is a generic widget.** A modal bottom sheet that takes a `PermissionResult`, a feature-specific copy string, and an optional `onSettingsTap` callback. It does not render until a denial actually happens, but consumers always pass it as the fallback path when a request returns non-`granted`.
- **No allowlist exemption needed.** `permission_handler` is not on the offline-imports forbidden list — it's an OS API wrapper, not a network client. The forbidden-imports gate stays clean.
- **No `RepositoryProvider` for tests** — the service is provided at the app root in `main.dart`. Tests construct it directly.
- **Test against a fake.** `FakePermissionsService` returns scripted results per call. We do **not** unit-test against `permission_handler` itself; that's an integration concern.

## Implementation

### A. Files to create

```
lib/services/permissions/
├── permissions_service.dart
└── permission_result.dart

lib/widgets/permissions/
└── permission_explainer_sheet.dart

test/services/permissions/
└── fake_permissions_service.dart

test/widgets/permissions/
└── permission_explainer_sheet_test.dart
```

### B. `lib/services/permissions/permission_result.dart`

```dart
/// Outcome of a permission request or status check. Mirrors the plugin's
/// underlying status enum but lives in our own namespace so plugin churn
/// doesn't ripple through the codebase.
enum PermissionResult {
  /// User granted the permission.
  granted,

  /// User denied this time but may re-prompt on a later request.
  denied,

  /// User selected "Don't ask again" / disabled in Settings. The OS will
  /// not prompt again until the user toggles it on in Settings.
  permanentlyDenied,

  /// Restricted by parental controls or device policy. Not user-toggleable.
  restricted,

  /// iOS 14+ photos: user granted access to a curated subset only. The
  /// app should treat this like granted but with a smaller set of assets.
  limited;

  bool get isUsable => this == granted || this == limited;
  bool get isFinalDenial => this == permanentlyDenied || this == restricted;
}
```

### C. `lib/services/permissions/permissions_service.dart`

```dart
import 'package:permission_handler/permission_handler.dart' as ph;

import 'permission_result.dart';

abstract class PermissionsService {
  // Microphone — for audio note capture, dictation (STT).
  Future<PermissionResult> requestMicrophone();
  Future<PermissionResult> microphoneStatus();

  // Camera — for in-app photo capture in image notes.
  Future<PermissionResult> requestCamera();
  Future<PermissionResult> cameraStatus();

  // Photos / Photo library — for picking images from the gallery.
  Future<PermissionResult> requestPhotos();
  Future<PermissionResult> photosStatus();

  // Notifications — for scheduled reminders via flutter_local_notifications.
  Future<PermissionResult> requestNotifications();
  Future<PermissionResult> notificationsStatus();

  // Bluetooth scan — for P2P peer discovery.
  Future<PermissionResult> requestBluetoothScan();
  Future<PermissionResult> bluetoothScanStatus();

  // Bluetooth connect — for establishing the share session.
  Future<PermissionResult> requestBluetoothConnect();
  Future<PermissionResult> bluetoothConnectStatus();

  // Bluetooth advertise — for being a discoverable peer.
  Future<PermissionResult> requestBluetoothAdvertise();
  Future<PermissionResult> bluetoothAdvertiseStatus();

  // Nearby Wi-Fi devices — Android 13+ for Wi-Fi-Direct fallback.
  Future<PermissionResult> requestNearbyWifiDevices();
  Future<PermissionResult> nearbyWifiDevicesStatus();

  /// Opens the OS app-settings panel for this app. Use when a permission
  /// returns `permanentlyDenied` and the user wants to re-enable it.
  Future<void> openSettings();
}

class PluginPermissionsService implements PermissionsService {
  const PluginPermissionsService();

  @override
  Future<PermissionResult> requestMicrophone() => _request(ph.Permission.microphone);

  @override
  Future<PermissionResult> microphoneStatus() => _status(ph.Permission.microphone);

  @override
  Future<PermissionResult> requestCamera() => _request(ph.Permission.camera);

  @override
  Future<PermissionResult> cameraStatus() => _status(ph.Permission.camera);

  @override
  Future<PermissionResult> requestPhotos() => _request(ph.Permission.photos);

  @override
  Future<PermissionResult> photosStatus() => _status(ph.Permission.photos);

  @override
  Future<PermissionResult> requestNotifications() =>
      _request(ph.Permission.notification);

  @override
  Future<PermissionResult> notificationsStatus() =>
      _status(ph.Permission.notification);

  @override
  Future<PermissionResult> requestBluetoothScan() =>
      _request(ph.Permission.bluetoothScan);

  @override
  Future<PermissionResult> bluetoothScanStatus() =>
      _status(ph.Permission.bluetoothScan);

  @override
  Future<PermissionResult> requestBluetoothConnect() =>
      _request(ph.Permission.bluetoothConnect);

  @override
  Future<PermissionResult> bluetoothConnectStatus() =>
      _status(ph.Permission.bluetoothConnect);

  @override
  Future<PermissionResult> requestBluetoothAdvertise() =>
      _request(ph.Permission.bluetoothAdvertise);

  @override
  Future<PermissionResult> bluetoothAdvertiseStatus() =>
      _status(ph.Permission.bluetoothAdvertise);

  @override
  Future<PermissionResult> requestNearbyWifiDevices() =>
      _request(ph.Permission.nearbyWifiDevices);

  @override
  Future<PermissionResult> nearbyWifiDevicesStatus() =>
      _status(ph.Permission.nearbyWifiDevices);

  @override
  Future<void> openSettings() async {
    await ph.openAppSettings();
  }

  Future<PermissionResult> _request(ph.Permission p) async {
    final status = await p.request();
    return _map(status);
  }

  Future<PermissionResult> _status(ph.Permission p) async {
    final status = await p.status;
    return _map(status);
  }

  PermissionResult _map(ph.PermissionStatus s) => switch (s) {
        ph.PermissionStatus.granted => PermissionResult.granted,
        ph.PermissionStatus.denied => PermissionResult.denied,
        ph.PermissionStatus.permanentlyDenied =>
          PermissionResult.permanentlyDenied,
        ph.PermissionStatus.restricted => PermissionResult.restricted,
        ph.PermissionStatus.limited => PermissionResult.limited,
        ph.PermissionStatus.provisional => PermissionResult.granted,
      };
}
```

### D. `lib/widgets/permissions/permission_explainer_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/theme/tokens.dart';

class PermissionExplainerSheet extends StatelessWidget {
  const PermissionExplainerSheet({
    super.key,
    required this.title,
    required this.body,
    required this.result,
    required this.service,
  });

  final String title;
  final String body;
  final PermissionResult result;
  final PermissionsService service;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    required PermissionResult result,
    required PermissionsService service,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => PermissionExplainerSheet(
        title: title,
        body: body,
        result: result,
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showSettingsAction = result.isFinalDenial;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tokens.text.headlineMd),
          const SizedBox(height: 12),
          Text(body, style: tokens.text.bodyLg),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  showSettingsAction ? 'Not now' : 'OK',
                  style: TextStyle(color: tokens.colors.onSurfaceMuted),
                ),
              ),
              if (showSettingsAction) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await service.openSettings();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Open settings'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
```

### E. `lib/main.dart` — register the service

Add to the `MultiRepositoryProvider`:

```dart
RepositoryProvider<PermissionsService>.value(
  value: const PluginPermissionsService(),
),
```

### F. iOS `Info.plist` additions

Path: `ios/Runner/Info.plist`

Add usage descriptions for every permission the service exposes. iOS rejects builds at upload if the Info.plist is missing keys for permissions referenced by the app. Keys:

- `NSMicrophoneUsageDescription` — "Notinotes uses the microphone to record audio notes and dictation. Audio never leaves your device."
- `NSCameraUsageDescription` — "Notinotes uses the camera to capture photos for image notes. Photos stay on your device."
- `NSPhotoLibraryUsageDescription` — "Notinotes reads photos so you can attach them to notes. Notinotes never uploads anything."
- `NSPhotoLibraryAddUsageDescription` — "Notinotes saves images to your photo library when you export a note."
- `NSBluetoothAlwaysUsageDescription` — "Notinotes uses Bluetooth to share notes with nearby devices. Sharing is opt-in per session and never goes through the internet."
- `NSBluetoothPeripheralUsageDescription` — "Notinotes uses Bluetooth to share notes with nearby devices. Sharing is opt-in per session and never goes through the internet."
- `NSLocalNetworkUsageDescription` — "Notinotes discovers nearby devices over Wi-Fi for peer-to-peer note sharing. Notes never travel through the internet."
- `NSBonjourServices` — `_notinotes._tcp` (the service identifier the share spec will register).

The microphone, camera, and photo strings explicitly call out the offline guarantee — that's the project's distinguishing promise and it belongs in the request prompt.

### G. Android `AndroidManifest.xml` additions

Path: `android/app/src/main/AndroidManifest.xml`

Inside `<manifest>` (before `<application>`), add:

```xml
<!-- Audio + camera + photos (image notes) -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />

<!-- Notifications (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Bluetooth — Android 12+ runtime; legacy declarations for older devices -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />

<!-- Wi-Fi-Direct fallback for P2P share -->
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation"
    tools:targetApi="33" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
```

The `tools:targetApi="33"` attribute requires the `xmlns:tools="http://schemas.android.com/tools"` declaration on the `<manifest>` element if it's not already present.

Pre-Android-12 fallback declarations stay because users on Android 11 and earlier will install the APK; the modern flags are scoped via `maxSdkVersion`.

### H. `FakePermissionsService` for tests

`test/services/permissions/fake_permissions_service.dart`:

```dart
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';

/// Test double. Configure per-test by setting public fields; default = denied.
class FakePermissionsService implements PermissionsService {
  PermissionResult microphone = PermissionResult.denied;
  PermissionResult camera = PermissionResult.denied;
  PermissionResult photos = PermissionResult.denied;
  PermissionResult notifications = PermissionResult.denied;
  PermissionResult bluetoothScan = PermissionResult.denied;
  PermissionResult bluetoothConnect = PermissionResult.denied;
  PermissionResult bluetoothAdvertise = PermissionResult.denied;
  PermissionResult nearbyWifiDevices = PermissionResult.denied;
  bool settingsOpened = false;

  final List<String> requestLog = [];

  Future<PermissionResult> _log(String name, PermissionResult r) async {
    requestLog.add(name);
    return r;
  }

  @override
  Future<PermissionResult> requestMicrophone() => _log('microphone', microphone);
  @override
  Future<PermissionResult> microphoneStatus() async => microphone;

  @override
  Future<PermissionResult> requestCamera() => _log('camera', camera);
  @override
  Future<PermissionResult> cameraStatus() async => camera;

  @override
  Future<PermissionResult> requestPhotos() => _log('photos', photos);
  @override
  Future<PermissionResult> photosStatus() async => photos;

  @override
  Future<PermissionResult> requestNotifications() =>
      _log('notifications', notifications);
  @override
  Future<PermissionResult> notificationsStatus() async => notifications;

  @override
  Future<PermissionResult> requestBluetoothScan() =>
      _log('bluetoothScan', bluetoothScan);
  @override
  Future<PermissionResult> bluetoothScanStatus() async => bluetoothScan;

  @override
  Future<PermissionResult> requestBluetoothConnect() =>
      _log('bluetoothConnect', bluetoothConnect);
  @override
  Future<PermissionResult> bluetoothConnectStatus() async => bluetoothConnect;

  @override
  Future<PermissionResult> requestBluetoothAdvertise() =>
      _log('bluetoothAdvertise', bluetoothAdvertise);
  @override
  Future<PermissionResult> bluetoothAdvertiseStatus() async => bluetoothAdvertise;

  @override
  Future<PermissionResult> requestNearbyWifiDevices() =>
      _log('nearbyWifiDevices', nearbyWifiDevices);
  @override
  Future<PermissionResult> nearbyWifiDevicesStatus() async => nearbyWifiDevices;

  @override
  Future<void> openSettings() async {
    settingsOpened = true;
  }
}
```

### I. Update `context/architecture.md`

Add to the **Stack** table:

| `PermissionsService` | `permission_handler` 12.x via wrapper | Point-of-use permission orchestration |

Add to the **System boundaries → cross-cutting services** list: `lib/services/permissions/`.

Reaffirm invariant 9 ("Permissions requested at point of use…") with the wrapper note: *every consumer goes through `PermissionsService`; direct `permission_handler` imports under `lib/` are forbidden by code review.*

### J. Update `context/code-standards.md`

Append to **Forbidden imports** (separate from the offline-imports list — this is a *cleanliness* gate, not a network gate):

```markdown
The following imports are also forbidden under `lib/` for hygiene reasons (not enforced by `scripts/check-offline.sh` because they are not network-related):

- `package:permission_handler` — go through `PermissionsService` instead.
- `package:flutter_local_notifications` (raw) — go through `NotificationsService` (created in a future spec).
```

### K. Update `context/progress-tracker.md`

- Mark Spec 12 complete.
- Add **Architecture decisions** entry 20: `PermissionsService` instance class with typed `PermissionResult` enum; one method per permission; iOS Info.plist + Android manifest entries land in this spec.
- Add **Open questions** entry 13: should we add a CI grep gate for direct `permission_handler` imports under `lib/`? (Probably yes; deferred until we add the same gate for `flutter_local_notifications` when its service wrapper lands.)

## Success Criteria

- [ ] Files in Section A exist and `PluginPermissionsService` implements every `PermissionsService` method.
- [ ] `lib/main.dart` registers `RepositoryProvider<PermissionsService>` at the app root.
- [ ] `ios/Runner/Info.plist` contains every key listed in Section F with the offline-emphasizing copy.
- [ ] `android/app/src/main/AndroidManifest.xml` contains every `<uses-permission>` listed in Section G with correct `maxSdkVersion` / `tools:targetApi` attributes.
- [ ] `flutter analyze` exits 0; offline gate clean; format clean.
- [ ] `flutter test` exits 0 with at least:
  - `permission_explainer_sheet_test.dart` — verifies the "Open settings" button appears only when `result.isFinalDenial` is true and dispatches `service.openSettings()` when tapped.
  - The `FakePermissionsService` is exercised by simply being constructable + setting fields + verifying `requestLog` order.
- [ ] **Manual smoke**:
  - Fresh install on iOS: open user_info → tap profile picture → camera prompt appears with the offline-emphasizing copy. Deny → next tap shows the explainer sheet → "Open settings" → app settings opens.
  - Fresh install on Android 13: notification reminder is set on a note → OS prompts for `POST_NOTIFICATIONS` once → user grants → reminder fires.
  - No permission is requested at app launch; only when the user takes an action that needs it.
- [ ] No file under `lib/` outside `lib/services/permissions/` imports `package:permission_handler`. Verify with `grep -RnE "package:permission_handler" lib/ | grep -v "lib/services/permissions"`.
- [ ] No new runtime dependencies (`permission_handler` is already in `pubspec.yaml`).
- [ ] No invariant in `context/architecture.md` is changed.

## References

- [`context/architecture.md`](../context/architecture.md) — invariant 9 (permissions at point of use)
- [`context/code-standards.md`](../context/code-standards.md) — extended in Section J
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-flutter-patterns`](../.agents/skills/dart-flutter-patterns/SKILL.md)
- Agent: `flutter-expert` — invoke after the manifest changes to verify nothing leaks into release builds (Android `tools:` namespace, iOS string keys)
- Agent: `code-reviewer` — confirm no consumer imports `permission_handler` directly
- Plugin docs: <https://pub.dev/packages/permission_handler>
- Follow-up: Spec 13 (audio capture) is the first runtime consumer of `requestMicrophone()`.

# 17 — device-capability-service

## Goal

Add a **typed device capability service** that probes RAM, OS version, CPU architecture, and (on iOS) Metal support, then exposes the result through `DeviceCapabilityService`. The result drives whether AI features (LLM assist, Whisper transcription) and platform-conditional features (Wi-Fi-Direct on Android 13+, on-device STT) render at all. Per [architecture.md](../context/architecture.md) invariant 2, every AI entry point checks this service before rendering its affordance — no half-rendered "loading model" state on a phone that can't run it. Probe results are cached in `SettingsRepository` and re-probed only when the OS version changes.

## Dependencies

- [10-theme-tokens](10-theme-tokens.md), [12-permissions-service](12-permissions-service.md) — service plumbing pattern.

## Agents & skills

**Pre-coding skills:**
- `dart-flutter-patterns` — typed-tier enum + cached-result service pattern.

**After-coding agents:**
- `flutter-expert` — verify the probe correctly classifies test devices across iOS + Android tiers; cache invalidation on OS-version change is honored.

## Design Decisions

- **Package**: `device_info_plus` (^11.x, official by `fluttercommunity`).
- **Two probe windows**: one on cold start (sync against cached values), one on demand when the user taps "Enable AI assist" (re-probe in case OS upgraded).
- **Typed capability tiers** rather than raw numbers. The service exposes:
  - `AiTier.full` — RAM ≥ 6 GB, iOS 16+ / Android 13+, ARM64. Runs Gemma 2-2B comfortably.
  - `AiTier.compact` — RAM 4–6 GB. Runs Phi-3-mini-4k or Qwen2.5-1.5B with quantization.
  - `AiTier.unsupported` — RAM < 4 GB or unsupported OS / arch.
- **Exposed values** for UI: `ramBytes`, `osMajorVersion`, `archIsArm64`, `hasMetal` (iOS-only), `hasNeuralEngine` (iOS-only, A12+).
- **Probe is async, result is sync after first call**. After bootstrap, `DeviceCapabilityService.aiTier` and friends return synchronously from cache.
- **Re-probe trigger**: a stored `lastProbedOsVersion` value; if the current OS version differs, re-probe automatically and update the cache.
- **No network**: `device_info_plus` reads only system properties; verified clean against the offline gate.

## Implementation

### A. Files

```
lib/services/device/
├── device_capability_service.dart
├── ai_tier.dart
└── device_capability_probe.dart      ← async probe; runs on bootstrap

test/services/device/
└── fake_device_capability_service.dart
```

### B. `pubspec.yaml`

```yaml
dependencies:
  device_info_plus: ^11.2.0
```

### C. `ai_tier.dart`

```dart
enum AiTier {
  /// ≥6 GB RAM, modern OS, arm64. Full LLM + Whisper.
  full,
  /// 4–6 GB RAM. Quantized LLM + Whisper-tiny.
  compact,
  /// Below threshold. AI hidden.
  unsupported;

  bool get canRunLlm => this != unsupported;
  bool get canRunWhisper => this != unsupported;
}
```

### D. `device_capability_service.dart`

```dart
import 'ai_tier.dart';

abstract class DeviceCapabilityService {
  /// Sync after first probe. Throws StateError if probe hasn't run.
  AiTier get aiTier;
  int get ramBytes;
  int get osMajorVersion;
  bool get archIsArm64;
  bool get hasMetal;        // iOS only; false on Android
  bool get hasNeuralEngine; // iOS A12+; false on Android

  /// Re-probes against the OS. Fires when the user explicitly opts into AI.
  Future<void> reprobe();
}

class CachedDeviceCapabilityService implements DeviceCapabilityService {
  CachedDeviceCapabilityService({
    required this.aiTier,
    required this.ramBytes,
    required this.osMajorVersion,
    required this.archIsArm64,
    required this.hasMetal,
    required this.hasNeuralEngine,
  });

  // (override re-probe to delegate to a probe + update cache; full impl in spec 18)
  // ...
}
```

### E. `device_capability_probe.dart`

Concrete probe using `device_info_plus`. iOS branch reads `IosDeviceInfo.systemVersion`, `utsname.machine` for chip family, and `physicalMemory` (post 11.x). Android branch reads `AndroidDeviceInfo.version.sdkInt` and physical memory via the `MemoryInfo` channel; arch via `Build.SUPPORTED_ABIS`.

Tier classifier:

```dart
AiTier classify({
  required int ramBytes,
  required int osMajorVersion,
  required bool archIsArm64,
  required bool isIos,
}) {
  if (!archIsArm64) return AiTier.unsupported;
  final ramGb = ramBytes / (1024 * 1024 * 1024);
  final modernOs = isIos ? osMajorVersion >= 16 : osMajorVersion >= 33; // Android 13
  if (!modernOs) return AiTier.unsupported;
  if (ramGb >= 5.5) return AiTier.full;
  if (ramGb >= 3.5) return AiTier.compact;
  return AiTier.unsupported;
}
```

### F. Bootstrap

`lib/main.dart`:

```dart
final caps = await DeviceCapabilityProbe().probe(settings: settingsRepository);
RepositoryProvider<DeviceCapabilityService>.value(value: caps),
```

### G. `SettingsRepository` extension

Cache keys: `aiTier` (string enum), `ramBytes` (int), `osMajorVersion` (int), `archIsArm64` (bool), `hasMetal` (bool), `hasNeuralEngine` (bool), `lastProbedOsVersion` (string).

## Success Criteria

- [ ] Files in Section A exist; service registered in `main.dart`; cache works.
- [ ] On a 4 GB RAM Pixel 4a (Android 13): `aiTier == AiTier.compact`.
- [ ] On a 1 GB RAM Android emulator: `aiTier == AiTier.unsupported`.
- [ ] On an iPhone 12 (6 GB RAM, iOS 17): `aiTier == AiTier.full`, `hasMetal == true`, `hasNeuralEngine == true`.
- [ ] `flutter analyze` / format / test clean; offline gate clean.
- [ ] No invariant changed.

## References

- [`context/architecture.md`](../context/architecture.md) — invariant 2 (AI gated by device caps)
- Plugin: <https://pub.dev/packages/device_info_plus>
- Follow-up: Spec 18 (LLM runtime validation) consumes the tier; Spec 21 (Whisper) too.

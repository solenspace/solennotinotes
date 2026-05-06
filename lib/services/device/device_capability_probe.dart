import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:meta/meta.dart';

import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';

/// Cold-start device-capability probe (Spec 17). Two probe windows: one at
/// app boot from `main.dart`, one on demand when the user opts into AI
/// (Spec 18) by calling [DeviceCapabilityService.reprobe]. Cached values
/// in [SettingsRepository] short-circuit the plugin handshake on subsequent
/// cold starts; a change in `Platform.operatingSystemVersion` invalidates
/// the cache automatically.
///
/// Conservative by design: any failure path resolves to
/// [AiTier.unsupported] with all flags false, matching `architecture.md`
/// invariant 2 ("below threshold, the affordance does not render"). Same
/// posture as [SttCapabilityProbe].
class DeviceCapabilityProbe {
  const DeviceCapabilityProbe();

  Future<CachedDeviceCapabilityService> probe({
    required SettingsRepository settings,
  }) async {
    final currentOsVersion = Platform.operatingSystemVersion;
    final cachedOsVersion = await settings.getLastProbedOsVersion();

    if (cachedOsVersion == currentOsVersion) {
      final hydrated = await _hydrateFromCache(settings);
      if (hydrated != null) return hydrated;
    }

    final raw = await _probePlatform();
    final tier = classify(
      ramBytes: raw.ramBytes,
      osMajorVersion: raw.osMajorVersion,
      archIsArm64: raw.archIsArm64,
      isIos: Platform.isIOS,
    );

    await _persist(settings, raw, tier, currentOsVersion);

    return CachedDeviceCapabilityService(
      aiTier: tier,
      ramBytes: raw.ramBytes,
      osMajorVersion: raw.osMajorVersion,
      archIsArm64: raw.archIsArm64,
      hasMetal: raw.hasMetal,
      hasNeuralEngine: raw.hasNeuralEngine,
      settings: settings,
      probe: this,
    );
  }

  Future<CachedDeviceCapabilityService?> _hydrateFromCache(
    SettingsRepository settings,
  ) async {
    final aiTierName = await settings.getAiTier();
    final ramBytes = await settings.getRamBytes();
    final osMajorVersion = await settings.getOsMajorVersion();
    final archIsArm64 = await settings.getArchIsArm64();
    final hasMetal = await settings.getHasMetal();
    final hasNeuralEngine = await settings.getHasNeuralEngine();

    if (aiTierName == null ||
        ramBytes == null ||
        osMajorVersion == null ||
        archIsArm64 == null ||
        hasMetal == null ||
        hasNeuralEngine == null) {
      return null;
    }

    return CachedDeviceCapabilityService(
      aiTier: aiTierFromName(aiTierName),
      ramBytes: ramBytes,
      osMajorVersion: osMajorVersion,
      archIsArm64: archIsArm64,
      hasMetal: hasMetal,
      hasNeuralEngine: hasNeuralEngine,
      settings: settings,
      probe: this,
    );
  }

  Future<_RawCapabilities> _probePlatform() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final osMajor = parseLeadingInt(ios.systemVersion);
        // physicalRamSize is exposed as an int in megabytes by
        // device_info_plus 11.x. Convert to bytes for the classifier.
        final ramBytes = ios.physicalRamSize > 0 ? ios.physicalRamSize * 1024 * 1024 : 0;
        final machine = ios.utsname.machine;
        return _RawCapabilities(
          ramBytes: ramBytes,
          osMajorVersion: osMajor,
          // Every iPhone shipped after 2013 (5s onward) is arm64. Anything
          // older is below the iOS-16 OS gate so the arch flag is academic.
          archIsArm64: machine.isNotEmpty,
          hasMetal: osMajor >= 8,
          hasNeuralEngine: iosMachineHasNeuralEngine(machine),
        );
      }
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final ramBytes = android.physicalRamSize > 0 ? android.physicalRamSize * 1024 * 1024 : 0;
        return _RawCapabilities(
          ramBytes: ramBytes,
          osMajorVersion: android.version.sdkInt,
          archIsArm64: android.supportedAbis.contains('arm64-v8a'),
          hasMetal: false,
          hasNeuralEngine: false,
        );
      }
    } on Object {
      // fall through to defaults
    }
    return const _RawCapabilities(
      ramBytes: 0,
      osMajorVersion: 0,
      archIsArm64: false,
      hasMetal: false,
      hasNeuralEngine: false,
    );
  }

  Future<void> _persist(
    SettingsRepository settings,
    _RawCapabilities raw,
    AiTier tier,
    String osVersionString,
  ) async {
    await settings.setAiTier(aiTierAsName(tier));
    await settings.setRamBytes(raw.ramBytes);
    await settings.setOsMajorVersion(raw.osMajorVersion);
    await settings.setArchIsArm64(raw.archIsArm64);
    await settings.setHasMetal(raw.hasMetal);
    await settings.setHasNeuralEngine(raw.hasNeuralEngine);
    await settings.setLastProbedOsVersion(osVersionString);
  }

  /// Parses the leading integer from a version string such as
  /// `"17.4.1"` (iOS) → `17`. Returns `0` when no leading digit is
  /// present so callers treat the device as failing the OS gate.
  @visibleForTesting
  static int parseLeadingInt(String version) {
    final match = RegExp(r'^(\d+)').firstMatch(version);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}

/// Whether [machine] (the value of `utsname.machine` on iOS) corresponds
/// to a device with an Apple Neural Engine — A12 Bionic and later. The
/// A12 shipped in `iPhone11,*` (XS / XR, 2018) and `iPad8,*` (iPad Pro
/// 2018); every later identifier qualifies.
///
/// Conservative on garbage input: unknown formats return `false` rather
/// than guess.
@visibleForTesting
bool iosMachineHasNeuralEngine(String machine) {
  if (machine.isEmpty) return false;
  // Simulator under Xcode reports `arm64` / `x86_64`; treat the simulator
  // as not-Neural-Engine so the developer experience matches the lowest
  // common test device.
  if (!machine.contains(',')) return false;
  final iPhone = RegExp(r'^iPhone(\d+),');
  final iPad = RegExp(r'^iPad(\d+),');
  final iPhoneMatch = iPhone.firstMatch(machine);
  if (iPhoneMatch != null) {
    final major = int.tryParse(iPhoneMatch.group(1)!);
    return major != null && major >= 11;
  }
  final iPadMatch = iPad.firstMatch(machine);
  if (iPadMatch != null) {
    final major = int.tryParse(iPadMatch.group(1)!);
    return major != null && major >= 8;
  }
  return false;
}

/// Pure-function tier classifier exposed for unit testing. The probe
/// calls this with the values it read from the platform; the result is
/// what gets persisted as [SettingsRepository.aiTier].
///
/// Spec 17 § E baseline plus one targeted addition: on Android the OEM
/// occasionally returns `0` for `physicalRamSize`. Rather than dropping
/// such devices to [AiTier.unsupported] (which would hide AI for a
/// large slice of healthy hardware), unknown-but-modern arm64 Android
/// is mapped to [AiTier.compact] — the spec's documented baseline for
/// Whisper-tiny + quantized Phi-3.
@visibleForTesting
AiTier classify({
  required int ramBytes,
  required int osMajorVersion,
  required bool archIsArm64,
  required bool isIos,
}) {
  if (!archIsArm64) return AiTier.unsupported;
  final modernOs = isIos ? osMajorVersion >= 16 : osMajorVersion >= 33;
  if (!modernOs) return AiTier.unsupported;
  if (!isIos && ramBytes == 0) return AiTier.compact;
  final ramGb = ramBytes / (1024 * 1024 * 1024);
  if (ramGb >= 5.5) return AiTier.full;
  if (ramGb >= 3.5) return AiTier.compact;
  return AiTier.unsupported;
}

class _RawCapabilities {
  const _RawCapabilities({
    required this.ramBytes,
    required this.osMajorVersion,
    required this.archIsArm64,
    required this.hasMetal,
    required this.hasNeuralEngine,
  });

  final int ramBytes;
  final int osMajorVersion;
  final bool archIsArm64;
  final bool hasMetal;
  final bool hasNeuralEngine;
}

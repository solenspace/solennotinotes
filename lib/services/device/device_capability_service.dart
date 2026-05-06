import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_probe.dart';

/// Read-only contract over the device-capability cache (Spec 17). Every AI
/// affordance (Specs 18, 21) consults [aiTier] before rendering — see
/// `architecture.md` invariant 2.
///
/// Getters are sync after the cold-start probe in `main.dart` resolves;
/// constructing a service via any other path would violate that
/// expectation and is not supported.
abstract class DeviceCapabilityService {
  AiTier get aiTier;

  /// Total physical RAM in bytes. `0` when the platform did not report a
  /// value (Android OEM corner cases) — the classifier treats this as
  /// "unknown" rather than "no RAM".
  int get ramBytes;

  /// iOS major version (e.g. 17) on iOS; Android API level (e.g. 33) on
  /// Android.
  int get osMajorVersion;

  bool get archIsArm64;

  /// iOS-only signal. Always `false` on Android.
  bool get hasMetal;

  /// iOS-only signal — Apple Neural Engine (A12+ / iPhone XS and later;
  /// iPad Pro 2018 and later). Always `false` on Android.
  bool get hasNeuralEngine;

  /// Re-runs the probe against the live OS and updates the cache. Fires
  /// when the user explicitly opts into AI (Spec 18) so an OS upgrade
  /// after the cold-start probe is honoured before any model load.
  ///
  /// Probe failure leaves the existing cached values intact (conservative,
  /// mirrors the cold-start path).
  Future<void> reprobe();
}

/// Concrete [DeviceCapabilityService] backed by mutable fields seeded at
/// construction time and updated by [reprobe]. Instances are produced by
/// [DeviceCapabilityProbe.probe] and registered as a singleton via
/// `RepositoryProvider` in `main.dart`.
class CachedDeviceCapabilityService implements DeviceCapabilityService {
  CachedDeviceCapabilityService({
    required AiTier aiTier,
    required int ramBytes,
    required int osMajorVersion,
    required bool archIsArm64,
    required bool hasMetal,
    required bool hasNeuralEngine,
    required SettingsRepository settings,
    DeviceCapabilityProbe probe = const DeviceCapabilityProbe(),
  })  : _aiTier = aiTier,
        _ramBytes = ramBytes,
        _osMajorVersion = osMajorVersion,
        _archIsArm64 = archIsArm64,
        _hasMetal = hasMetal,
        _hasNeuralEngine = hasNeuralEngine,
        _settings = settings,
        _probe = probe;

  AiTier _aiTier;
  int _ramBytes;
  int _osMajorVersion;
  bool _archIsArm64;
  bool _hasMetal;
  bool _hasNeuralEngine;

  final SettingsRepository _settings;
  final DeviceCapabilityProbe _probe;

  @override
  AiTier get aiTier => _aiTier;

  @override
  int get ramBytes => _ramBytes;

  @override
  int get osMajorVersion => _osMajorVersion;

  @override
  bool get archIsArm64 => _archIsArm64;

  @override
  bool get hasMetal => _hasMetal;

  @override
  bool get hasNeuralEngine => _hasNeuralEngine;

  @override
  Future<void> reprobe() async {
    try {
      final fresh = await _probe.probe(settings: _settings);
      _aiTier = fresh.aiTier;
      _ramBytes = fresh.ramBytes;
      _osMajorVersion = fresh.osMajorVersion;
      _archIsArm64 = fresh.archIsArm64;
      _hasMetal = fresh.hasMetal;
      _hasNeuralEngine = fresh.hasNeuralEngine;
    } on Object {
      // Conservative: leave cached values intact on any failure path.
    }
  }
}

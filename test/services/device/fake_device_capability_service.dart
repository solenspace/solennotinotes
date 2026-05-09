import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';

/// Test double for [DeviceCapabilityService]. Configure per-test by
/// setting public fields; defaults to the conservative
/// [AiTier.unsupported] / all-flags-false steady state so tests opt into
/// AI rather than out of it.
class FakeDeviceCapabilityService implements DeviceCapabilityService {
  @override
  AiTier aiTier = AiTier.unsupported;

  @override
  int ramBytes = 0;

  @override
  int osMajorVersion = 0;

  @override
  bool archIsArm64 = false;

  @override
  bool hasMetal = false;

  @override
  bool hasNeuralEngine = false;

  int reprobeCount = 0;
  Object? reprobeError;

  @override
  Future<void> reprobe() async {
    reprobeCount++;
    final error = reprobeError;
    if (error != null) throw error;
  }
}

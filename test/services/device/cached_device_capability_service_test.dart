import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_probe.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';

import '../../repositories/settings/fake_settings_repository.dart';

void main() {
  group('CachedDeviceCapabilityService', () {
    test('sync getters return the values seeded in the constructor', () {
      final settings = FakeSettingsRepository();
      final service = CachedDeviceCapabilityService(
        aiTier: AiTier.full,
        ramBytes: 8 * 1024 * 1024 * 1024,
        osMajorVersion: 17,
        archIsArm64: true,
        hasMetal: true,
        hasNeuralEngine: true,
        settings: settings,
        probe: const _NeverCalledProbe(),
      );

      expect(service.aiTier, AiTier.full);
      expect(service.ramBytes, 8 * 1024 * 1024 * 1024);
      expect(service.osMajorVersion, 17);
      expect(service.archIsArm64, isTrue);
      expect(service.hasMetal, isTrue);
      expect(service.hasNeuralEngine, isTrue);
    });

    test('reprobe() swaps cached values when the probe returns a new tier', () async {
      final settings = FakeSettingsRepository();
      final probe = _ScriptedProbe();
      final service = CachedDeviceCapabilityService(
        aiTier: AiTier.unsupported,
        ramBytes: 0,
        osMajorVersion: 0,
        archIsArm64: false,
        hasMetal: false,
        hasNeuralEngine: false,
        settings: settings,
        probe: probe,
      );

      probe.next = CachedDeviceCapabilityService(
        aiTier: AiTier.full,
        ramBytes: 6 * 1024 * 1024 * 1024,
        osMajorVersion: 17,
        archIsArm64: true,
        hasMetal: true,
        hasNeuralEngine: true,
        settings: settings,
        probe: const _NeverCalledProbe(),
      );

      await service.reprobe();

      expect(service.aiTier, AiTier.full);
      expect(service.ramBytes, 6 * 1024 * 1024 * 1024);
      expect(service.osMajorVersion, 17);
      expect(service.archIsArm64, isTrue);
      expect(service.hasMetal, isTrue);
      expect(service.hasNeuralEngine, isTrue);
      expect(probe.calls, 1);
    });

    test('reprobe() leaves cached values intact when the probe throws', () async {
      final settings = FakeSettingsRepository();
      final probe = _ScriptedProbe()..error = StateError('platform threw');
      final service = CachedDeviceCapabilityService(
        aiTier: AiTier.compact,
        ramBytes: 4 * 1024 * 1024 * 1024,
        osMajorVersion: 33,
        archIsArm64: true,
        hasMetal: false,
        hasNeuralEngine: false,
        settings: settings,
        probe: probe,
      );

      await service.reprobe();

      expect(service.aiTier, AiTier.compact);
      expect(service.ramBytes, 4 * 1024 * 1024 * 1024);
      expect(service.osMajorVersion, 33);
      expect(service.archIsArm64, isTrue);
      expect(service.hasMetal, isFalse);
      expect(service.hasNeuralEngine, isFalse);
      expect(probe.calls, 1);
    });
  });
}

class _NeverCalledProbe implements DeviceCapabilityProbe {
  const _NeverCalledProbe();
  @override
  Future<CachedDeviceCapabilityService> probe({required SettingsRepository settings}) {
    fail('probe() was not expected to be called in this test');
  }
}

class _ScriptedProbe implements DeviceCapabilityProbe {
  CachedDeviceCapabilityService? next;
  Object? error;
  int calls = 0;

  @override
  Future<CachedDeviceCapabilityService> probe({required SettingsRepository settings}) async {
    calls++;
    final err = error;
    if (err != null) throw err;
    final result = next;
    if (result == null) {
      fail('test must seed `next` before calling probe()');
    }
    return result;
  }
}

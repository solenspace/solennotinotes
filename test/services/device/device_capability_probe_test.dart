import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_probe.dart';

void main() {
  group('classify', () {
    test('iOS 17 + arm64 + 7 GB ⇒ full', () {
      expect(
        classify(
          ramBytes: 7 * 1024 * 1024 * 1024,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.full,
      );
    });

    test('iOS 15 + arm64 + 7 GB ⇒ unsupported (OS gate)', () {
      expect(
        classify(
          ramBytes: 7 * 1024 * 1024 * 1024,
          osMajorVersion: 15,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.unsupported,
      );
    });

    test('iOS 16 + arm64 + 3 GB ⇒ unsupported (RAM gate)', () {
      expect(
        classify(
          ramBytes: 3 * 1024 * 1024 * 1024,
          osMajorVersion: 16,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.unsupported,
      );
    });

    test('iOS 16 + arm64 + 4 GB ⇒ compact', () {
      expect(
        classify(
          ramBytes: 4 * 1024 * 1024 * 1024,
          osMajorVersion: 16,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.compact,
      );
    });

    test('Android 13 + arm64 + 4 GB ⇒ compact', () {
      expect(
        classify(
          ramBytes: 4 * 1024 * 1024 * 1024,
          osMajorVersion: 33,
          archIsArm64: true,
          isIos: false,
        ),
        AiTier.compact,
      );
    });

    test('Android 13 + arm64 + 8 GB ⇒ full', () {
      expect(
        classify(
          ramBytes: 8 * 1024 * 1024 * 1024,
          osMajorVersion: 33,
          archIsArm64: true,
          isIos: false,
        ),
        AiTier.full,
      );
    });

    test('Android 13 + arm64 + RAM unknown (0 bytes) ⇒ compact', () {
      // Android OEMs occasionally return 0 from physicalRamSize; treating
      // such devices as unsupported would hide AI for healthy hardware.
      expect(
        classify(
          ramBytes: 0,
          osMajorVersion: 33,
          archIsArm64: true,
          isIos: false,
        ),
        AiTier.compact,
      );
    });

    test('Android 12 + arm64 + 8 GB ⇒ unsupported (OS gate)', () {
      expect(
        classify(
          ramBytes: 8 * 1024 * 1024 * 1024,
          osMajorVersion: 32,
          archIsArm64: true,
          isIos: false,
        ),
        AiTier.unsupported,
      );
    });

    test('Android 13 + armv7 (non-arm64) ⇒ unsupported', () {
      expect(
        classify(
          ramBytes: 8 * 1024 * 1024 * 1024,
          osMajorVersion: 33,
          archIsArm64: false,
          isIos: false,
        ),
        AiTier.unsupported,
      );
    });

    test('iOS unknown RAM (0 bytes) ⇒ unsupported (no Android-style fallback)', () {
      // iOS reliably reports physicalRamSize; a zero result is a probe
      // failure, not an OEM quirk, so the conservative posture is to
      // hide AI rather than gamble.
      expect(
        classify(
          ramBytes: 0,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.unsupported,
      );
    });

    test('boundary: exactly 5.5 GB ⇒ full', () {
      final ramBytes = (5.5 * 1024 * 1024 * 1024).round();
      expect(
        classify(
          ramBytes: ramBytes,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.full,
      );
    });

    test('boundary: just below 5.5 GB ⇒ compact', () {
      final ramBytes = (5.4 * 1024 * 1024 * 1024).round();
      expect(
        classify(
          ramBytes: ramBytes,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.compact,
      );
    });

    test('boundary: exactly 3.5 GB ⇒ compact', () {
      final ramBytes = (3.5 * 1024 * 1024 * 1024).round();
      expect(
        classify(
          ramBytes: ramBytes,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.compact,
      );
    });

    test('boundary: just below 3.5 GB ⇒ unsupported', () {
      final ramBytes = (3.4 * 1024 * 1024 * 1024).round();
      expect(
        classify(
          ramBytes: ramBytes,
          osMajorVersion: 17,
          archIsArm64: true,
          isIos: true,
        ),
        AiTier.unsupported,
      );
    });
  });

  group('iosMachineHasNeuralEngine', () {
    test('iPhone10,3 (iPhone X, A11) ⇒ false (no Neural Engine inference)', () {
      // The A11 has a Neural Engine but it is not exposed to third-party
      // apps until iOS 12 + A12. Using `iPhone11,*` (XS, A12) as the
      // earliest first-party-eligible identifier matches Apple's own
      // CoreML deployment guidance.
      expect(iosMachineHasNeuralEngine('iPhone10,3'), isFalse);
    });

    test('iPhone11,2 (iPhone XS, A12) ⇒ true', () {
      expect(iosMachineHasNeuralEngine('iPhone11,2'), isTrue);
    });

    test('iPhone15,2 (iPhone 14 Pro, A16) ⇒ true', () {
      expect(iosMachineHasNeuralEngine('iPhone15,2'), isTrue);
    });

    test('iPad8,1 (iPad Pro 2018, A12X) ⇒ true', () {
      expect(iosMachineHasNeuralEngine('iPad8,1'), isTrue);
    });

    test('iPad7,1 (iPad Pro 2017, A10X) ⇒ false', () {
      expect(iosMachineHasNeuralEngine('iPad7,1'), isFalse);
    });

    test('arm64 (Xcode simulator) ⇒ false', () {
      // Simulator reports a chip name rather than a device identifier;
      // matching the lowest-common test device avoids fake-positives in
      // dev builds.
      expect(iosMachineHasNeuralEngine('arm64'), isFalse);
    });

    test('empty string ⇒ false', () {
      expect(iosMachineHasNeuralEngine(''), isFalse);
    });

    test('garbage input ⇒ false', () {
      expect(iosMachineHasNeuralEngine('iPhoneABC'), isFalse);
      expect(iosMachineHasNeuralEngine('something,else'), isFalse);
    });
  });
}

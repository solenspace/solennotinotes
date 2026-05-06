import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/speech/stt_capability_probe.dart';

void main() {
  group('SttCapabilityProbe.androidSdkIntFromVersion', () {
    test('parses the API <int> token in a typical Android version string', () {
      expect(
        SttCapabilityProbe.androidSdkIntFromVersion('Linux 5.10.66 #1 SMP API 33'),
        33,
      );
    });

    test('parses a higher SDK number', () {
      expect(
        SttCapabilityProbe.androidSdkIntFromVersion('build version API 34 release'),
        34,
      );
    });

    test('returns 0 when the API token is absent', () {
      expect(
        SttCapabilityProbe.androidSdkIntFromVersion('macOS 13.6.1'),
        0,
      );
    });

    test('returns 0 on an empty string', () {
      expect(SttCapabilityProbe.androidSdkIntFromVersion(''), 0);
    });

    test('handles multi-digit SDK versions correctly', () {
      // The 31-cutoff (Android 12) is the offline-capable threshold per
      // Spec 15. A version string carrying API 31 returns exactly 31.
      expect(
        SttCapabilityProbe.androidSdkIntFromVersion('Android API 31'),
        31,
      );
    });
  });
}

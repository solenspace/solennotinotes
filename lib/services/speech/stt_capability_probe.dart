import 'dart:io';

import 'package:meta/meta.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Cold-start probe that decides whether this device can run STT fully
/// offline. Result is cached by `main()` in
/// [SettingsRepository.sttOfflineCapable]; the dictation UI hides itself
/// when the result is `false` (Spec 15 §"Hard offline gate").
///
/// Conservative by design: any failure or ambiguity yields `false`.
/// Android < 12 is treated as not-offline-capable because
/// `SpeechRecognizer.isOnDeviceRecognitionAvailable` lands in API 31.
class SttCapabilityProbe {
  const SttCapabilityProbe();

  Future<bool> probe() async {
    try {
      if (Platform.isAndroid) {
        if (androidSdkIntFromVersion(Platform.operatingSystemVersion) < 31) {
          return false;
        }
      }
      final speech = stt.SpeechToText();
      final ready = await speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
        debugLogging: false,
      );
      if (!ready) return false;
      if (Platform.isIOS) {
        return speech.isAvailable;
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Parses Android's `Platform.operatingSystemVersion` string for the
  /// `API <int>` token. Returns `0` when the token is absent so the caller
  /// treats the device as not-offline-capable.
  ///
  /// Refactor target: when Spec 17 (device-capability-service) lands, swap
  /// this for `DeviceInfoPlugin().androidInfo.version.sdkInt`.
  @visibleForTesting
  static int androidSdkIntFromVersion(String operatingSystemVersion) {
    final match = RegExp(r'API (\d+)').firstMatch(operatingSystemVersion);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}

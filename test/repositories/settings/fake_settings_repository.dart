import 'dart:async';

import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';

/// Test double for [SettingsRepository] backed by an in-memory record and a
/// broadcast controller. `watch()` yields the current snapshot first, then
/// forwards every controller event.
///
/// Implements the full [SettingsRepository] contract: the `Settings` value
/// object, the Spec 15 STT cache, the Spec 16 TTS cache, and the Spec 17
/// device-capability cache. Tests configure values by calling the matching
/// setters, or by mutating the public seed helpers.
class FakeSettingsRepository implements SettingsRepository {
  final StreamController<Settings> _controller = StreamController<Settings>.broadcast();
  Settings _store = Settings.defaults;

  final List<Settings> savedSettings = [];
  bool initCalled = false;
  NotiIdentityRepository? lastIdentityRepositoryArg;

  bool _sttOfflineCapable = false;
  String? _ttsVoice;
  double _ttsRate = 1.0;
  double _ttsPitch = 1.0;

  String? _aiTier;
  int? _ramBytes;
  int? _osMajorVersion;
  bool? _archIsArm64;
  bool? _hasMetal;
  bool? _hasNeuralEngine;
  String? _lastProbedOsVersion;

  @override
  Future<void> init({NotiIdentityRepository? identityRepository}) async {
    initCalled = true;
    lastIdentityRepositoryArg = identityRepository;
  }

  @override
  Future<Settings> getCurrent() async => _store;

  @override
  Stream<Settings> watch() async* {
    yield _store;
    yield* _controller.stream;
  }

  @override
  Future<void> save(Settings settings) async {
    savedSettings.add(settings);
    _store = settings;
    _controller.add(settings);
  }

  /// Test helper to seed an initial value before subscribers attach.
  void seed(Settings settings) {
    _store = settings;
  }

  Future<void> dispose() => _controller.close();

  bool get hasListener => _controller.hasListener;

  @override
  Future<bool> getSttOfflineCapable() async => _sttOfflineCapable;

  @override
  Future<void> setSttOfflineCapable(bool value) async {
    _sttOfflineCapable = value;
  }

  @override
  Future<String?> getTtsVoice() async => _ttsVoice;

  @override
  Future<void> setTtsVoice(String? value) async {
    _ttsVoice = value;
  }

  @override
  Future<double> getTtsRate() async => _ttsRate;

  @override
  Future<void> setTtsRate(double value) async {
    _ttsRate = value;
  }

  @override
  Future<double> getTtsPitch() async => _ttsPitch;

  @override
  Future<void> setTtsPitch(double value) async {
    _ttsPitch = value;
  }

  @override
  Future<String?> getAiTier() async => _aiTier;

  @override
  Future<void> setAiTier(String? value) async {
    _aiTier = value;
  }

  @override
  Future<int?> getRamBytes() async => _ramBytes;

  @override
  Future<void> setRamBytes(int? value) async {
    _ramBytes = value;
  }

  @override
  Future<int?> getOsMajorVersion() async => _osMajorVersion;

  @override
  Future<void> setOsMajorVersion(int? value) async {
    _osMajorVersion = value;
  }

  @override
  Future<bool?> getArchIsArm64() async => _archIsArm64;

  @override
  Future<void> setArchIsArm64(bool? value) async {
    _archIsArm64 = value;
  }

  @override
  Future<bool?> getHasMetal() async => _hasMetal;

  @override
  Future<void> setHasMetal(bool? value) async {
    _hasMetal = value;
  }

  @override
  Future<bool?> getHasNeuralEngine() async => _hasNeuralEngine;

  @override
  Future<void> setHasNeuralEngine(bool? value) async {
    _hasNeuralEngine = value;
  }

  @override
  Future<String?> getLastProbedOsVersion() async => _lastProbedOsVersion;

  @override
  Future<void> setLastProbedOsVersion(String? value) async {
    _lastProbedOsVersion = value;
  }
}

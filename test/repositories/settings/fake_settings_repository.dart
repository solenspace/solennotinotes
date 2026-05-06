import 'dart:async';

import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';

/// Test double for [SettingsRepository] backed by an in-memory record and a
/// broadcast controller. `watch()` yields the current snapshot first, then
/// forwards every controller event.
class FakeSettingsRepository implements SettingsRepository {
  final StreamController<Settings> _controller = StreamController<Settings>.broadcast();
  Settings _store = Settings.defaults;

  final List<Settings> savedSettings = [];
  bool initCalled = false;
  NotiIdentityRepository? lastIdentityRepositoryArg;

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
}

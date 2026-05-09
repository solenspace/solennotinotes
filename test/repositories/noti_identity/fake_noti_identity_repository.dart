import 'dart:async';
import 'dart:io';

import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';

/// Test double for [NotiIdentityRepository] backed by an in-memory record
/// and a broadcast controller. `watch()` yields the current snapshot first,
/// then forwards every controller event.
class FakeNotiIdentityRepository implements NotiIdentityRepository {
  final StreamController<NotiIdentity> _controller = StreamController<NotiIdentity>.broadcast();
  NotiIdentity? _store;

  final List<NotiIdentity> savedIdentities = [];
  final List<File> removedPhotos = [];
  final List<({NotiIdentity identity, File? newPhoto})> setPhotoCalls = [];
  bool initCalled = false;

  void emit(NotiIdentity identity) {
    _store = identity;
    _controller.add(identity);
  }

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<NotiIdentity> getCurrent() async {
    final stored = _store;
    if (stored != null) return stored;
    final fresh = NotiIdentity.fresh();
    _store = fresh;
    return fresh;
  }

  @override
  Stream<NotiIdentity> watch() async* {
    final snapshot = _store;
    if (snapshot != null) yield snapshot;
    yield* _controller.stream;
  }

  @override
  Future<void> save(NotiIdentity identity) async {
    savedIdentities.add(identity);
    _store = identity;
    _controller.add(identity);
  }

  @override
  Future<void> setPhoto(NotiIdentity identity, File? newPhoto) async {
    setPhotoCalls.add((identity: identity, newPhoto: newPhoto));
    final old = identity.profilePicture;
    if (old != null && old.path != newPhoto?.path) {
      removedPhotos.add(old);
    }
    identity.profilePicture = newPhoto;
    await save(identity);
  }

  @override
  Future<void> removePhoto(NotiIdentity identity) async {
    final old = identity.profilePicture;
    if (old == null) return;
    removedPhotos.add(old);
    identity.profilePicture = null;
    await save(identity);
  }

  Future<void> dispose() => _controller.close();

  bool get hasListener => _controller.hasListener;
}

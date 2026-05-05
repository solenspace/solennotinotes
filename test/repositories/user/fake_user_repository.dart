import 'dart:async';
import 'dart:io';

import 'package:noti_notes_app/models/user.dart';
import 'package:noti_notes_app/repositories/user/user_repository.dart';

/// Test double for [UserRepository] backed by an in-memory record and a
/// broadcast controller. `watch()` yields the current snapshot first, then
/// forwards every controller event.
class FakeUserRepository implements UserRepository {
  final StreamController<User?> _controller = StreamController<User?>.broadcast();
  User? _store;

  final List<User> savedUsers = [];
  final List<File> removedPhotos = [];
  final List<({User user, File? newPhoto})> setPhotoCalls = [];
  bool initCalled = false;

  void emit(User? user) {
    _store = user;
    _controller.add(user);
  }

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<User?> getCurrent() async => _store;

  @override
  Stream<User?> watch() async* {
    yield _store;
    yield* _controller.stream;
  }

  @override
  Future<void> save(User user) async {
    savedUsers.add(user);
    _store = user;
    _controller.add(user);
  }

  @override
  Future<void> setPhoto(User user, File? newPhoto) async {
    setPhotoCalls.add((user: user, newPhoto: newPhoto));
    final old = user.profilePicture;
    if (old != null && old.path != newPhoto?.path) {
      removedPhotos.add(old);
    }
    user.profilePicture = newPhoto;
    await save(user);
  }

  @override
  Future<void> removePhoto(User user) async {
    final old = user.profilePicture;
    if (old == null) return;
    removedPhotos.add(old);
    user.profilePicture = null;
    await save(user);
  }

  Future<void> dispose() => _controller.close();

  bool get hasListener => _controller.hasListener;
}

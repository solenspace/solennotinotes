import 'dart:io';

import 'package:noti_notes_app/models/user.dart';

/// Contract for the single-record user store. Concrete implementations may
/// target Hive (current), in-memory (tests), or a future on-device store.
abstract class UserRepository {
  /// Initialize backing storage. Must be called before any other method.
  /// Idempotent — multiple calls are safe.
  Future<void> init();

  /// Returns the current user, or `null` if no user record exists yet.
  Future<User?> getCurrent();

  /// Emits the current user on subscription, then on every save.
  /// Caller is responsible for cancelling the subscription.
  Stream<User?> watch();

  /// Persists the user. Overwrites any existing record.
  Future<void> save(User user);

  /// Replaces the profile picture file. Removes the previous file if any.
  Future<void> setPhoto(User user, File? newPhoto);

  /// Deletes the profile picture file and clears the field.
  Future<void> removePhoto(User user);
}

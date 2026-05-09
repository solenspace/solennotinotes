import 'dart:io';

import 'package:noti_notes_app/models/noti_identity.dart';

/// Contract for the single-record noti-identity store. Concrete
/// implementations may target Hive (current), in-memory (tests), or a
/// future on-device store.
abstract class NotiIdentityRepository {
  /// Initialize backing storage. Must be called before any other method.
  /// Idempotent — multiple calls are safe. Implementations are responsible
  /// for migrating from the legacy `user_v2` box on first launch and for
  /// generating a fresh identity when no record exists.
  Future<void> init();

  /// Returns the current identity. Implementations guarantee a record
  /// exists after [init], so this never returns null.
  Future<NotiIdentity> getCurrent();

  /// Emits the current identity on subscription, then on every save.
  /// Caller is responsible for cancelling the subscription.
  Stream<NotiIdentity> watch();

  /// Persists the identity. Overwrites any existing record. Throws
  /// [ArgumentError] when validation fails (multi-grapheme accent,
  /// tagline > 60 chars, empty palette).
  Future<void> save(NotiIdentity identity);

  /// Replaces the profile picture file. Removes the previous file if any.
  /// Mutates and persists the given [identity].
  Future<void> setPhoto(NotiIdentity identity, File? newPhoto);

  /// Deletes the profile picture file and clears the field. Mutates and
  /// persists the given [identity].
  Future<void> removePhoto(NotiIdentity identity);
}

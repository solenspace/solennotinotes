import 'package:noti_notes_app/models/note.dart';

/// Contract for note persistence. Concrete implementations may target
/// Hive (current), in-memory (tests), or a future on-device store.
abstract class NotesRepository {
  /// Initialize backing storage. Must be called before any other method.
  /// Idempotent — multiple calls are safe.
  Future<void> init();

  /// Returns all notes currently persisted, decoded into domain models.
  Future<List<Note>> getAll();

  /// Returns a stream that emits the full list whenever it changes.
  /// First emission is the current snapshot. Subsequent emissions fire on
  /// every put/delete/clear via Hive's `box.watch()`.
  /// Caller is responsible for cancelling the subscription.
  Stream<List<Note>> watchAll();

  /// Persists a note. Overwrites if an entry with the same id exists.
  Future<void> save(Note note);

  /// Persists multiple notes in sequence. No transactional guarantees.
  Future<void> saveAll(Iterable<Note> notes);

  /// Deletes a note by id and any on-disk image associated with it.
  /// Notification cancellation is the caller's responsibility.
  Future<void> delete(String id);

  /// Deletes multiple notes (and their images) by id.
  Future<void> deleteAll(Iterable<String> ids);

  /// Wipes every persisted note and every on-disk image in one shot.
  /// Used by settings → "clear all data".
  Future<void> clear();
}

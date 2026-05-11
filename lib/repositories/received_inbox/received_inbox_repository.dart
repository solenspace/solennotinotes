import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/received_share.dart';

/// Contract for the receiver-side share inbox (Spec 25). Concrete
/// implementations persist verified [ReceivedShare] entries until the
/// user accepts (merging into the notes library) or discards them.
abstract class ReceivedInboxRepository {
  /// Initialize backing storage. Must be called before any other method.
  /// Idempotent — multiple calls are safe.
  Future<void> init();

  /// Snapshot stream of all pending entries, newest-first by
  /// [ReceivedShare.receivedAt]. First emission is the current snapshot;
  /// subsequent emissions fire on insert/accept/discard. Caller is
  /// responsible for cancelling the subscription.
  Stream<List<ReceivedShare>> watchAll();

  /// One-shot snapshot in arrival order, newest-first.
  Future<List<ReceivedShare>> getAll();

  /// Persists a freshly-decoded share. Overwrites any prior entry with
  /// the same `share_id` (decoder-replay safety).
  Future<void> insert(ReceivedShare share);

  /// Promotes the share into the notes library:
  ///   1. Moves each image/audio asset from `<inboxRoot>/...` into
  ///      `<documents>/notes/<noteId>/{images,audio}/...`.
  ///   2. Rewrites the matching block's `path` to the new on-disk
  ///      location.
  ///   3. Reconstructs a [Note] (sender attribution + overlay-shaped
  ///      legacy fields populated from the manifest's overlay).
  ///   4. Saves to the notes repository.
  ///   5. Removes the inbox directory and the Hive entry.
  ///
  /// Returns the freshly-saved [Note]. Throws [StateError] when
  /// [shareId] is unknown.
  Future<Note> accept(String shareId);

  /// Drops the entry: removes the Hive record and recursively deletes
  /// `<inboxRoot>` so no asset bytes outlive the user's choice.
  Future<void> discard(String shareId);
}

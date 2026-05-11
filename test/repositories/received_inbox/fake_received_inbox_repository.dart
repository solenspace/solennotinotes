import 'dart:async';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';

/// In-memory [ReceivedInboxRepository] for tests. The `accept` path
/// fabricates a minimal [Note] derived from the inbox entry — enough to
/// flow through cubit / UI tests without standing up the filesystem.
class FakeReceivedInboxRepository implements ReceivedInboxRepository {
  FakeReceivedInboxRepository();

  final StreamController<List<ReceivedShare>> _controller =
      StreamController<List<ReceivedShare>>.broadcast();
  final Map<String, ReceivedShare> _entries = <String, ReceivedShare>{};

  final List<String> acceptedIds = [];
  final List<String> discardedIds = [];

  Note Function(ReceivedShare share)? noteBuilder;

  @override
  Future<void> init() async {}

  @override
  Stream<List<ReceivedShare>> watchAll() async* {
    yield _snapshot();
    yield* _controller.stream;
  }

  @override
  Future<List<ReceivedShare>> getAll() async => _snapshot();

  @override
  Future<void> insert(ReceivedShare share) async {
    _entries[share.shareId] = share;
    _controller.add(_snapshot());
  }

  @override
  Future<Note> accept(String shareId) async {
    final share = _entries.remove(shareId);
    if (share == null) {
      throw StateError('No inbox entry for shareId=$shareId');
    }
    acceptedIds.add(shareId);
    _controller.add(_snapshot());
    final builder = noteBuilder;
    if (builder != null) return builder(share);
    return Note(
      {},
      null,
      null,
      const <Map<String, dynamic>>[],
      null,
      null,
      id: share.note.id,
      title: share.note.title,
      content: '',
      dateCreated: share.note.dateCreated,
      colorBackground: share.note.overlay.surface,
      fontColor: share.note.overlay.onSurface ?? share.note.overlay.surface,
      hasGradient: false,
      isPinned: share.note.isPinned,
      blocks: share.note.blocks.map((b) => Map<String, dynamic>.from(b)).toList(),
      fromIdentityId: share.sender.id,
      fromDisplayName: share.sender.displayName,
      fromAccentGlyph: share.sender.signatureAccent,
    );
  }

  @override
  Future<void> discard(String shareId) async {
    if (_entries.remove(shareId) != null) {
      discardedIds.add(shareId);
      _controller.add(_snapshot());
    }
  }

  List<ReceivedShare> _snapshot() {
    final list = _entries.values.toList()..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return List<ReceivedShare>.unmodifiable(list);
  }

  Future<void> dispose() => _controller.close();
}

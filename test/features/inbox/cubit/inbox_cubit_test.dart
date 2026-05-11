import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_cubit.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_listener_service.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_state.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

import '../../../repositories/received_inbox/fake_received_inbox_repository.dart';

void main() {
  group('InboxCubit', () {
    late FakeReceivedInboxRepository repo;
    late _ScriptedListener listener;
    late InboxCubit cubit;

    setUp(() {
      repo = FakeReceivedInboxRepository();
      listener = _ScriptedListener();
      cubit = InboxCubit(repository: repo, listener: listener)..start();
    });

    tearDown(() async {
      await cubit.close();
      await repo.dispose();
    });

    test('state.entries tracks the repository snapshot', () async {
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.entries, isEmpty);

      await repo.insert(_share('a', DateTime.utc(2026, 5, 9, 10)));
      await repo.insert(_share('b', DateTime.utc(2026, 5, 9, 12)));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.entries.map((e) => e.shareId), ['b', 'a']);
    });

    test('startReceiving transitions starting → on', () async {
      final emitted = <InboxListenerStatus>[];
      final sub = cubit.stream.listen((s) => emitted.add(s.listener));

      await cubit.startReceiving();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, [InboxListenerStatus.starting, InboxListenerStatus.on]);
    });

    test('startReceiving failure → failed state with detail', () async {
      listener.startError = StateError('permission denied');
      await cubit.startReceiving();
      expect(cubit.state.listener, InboxListenerStatus.failed);
      expect(cubit.state.failureDetail, contains('permission denied'));
    });

    test('stopReceiving returns to off and clears failure detail', () async {
      listener.startError = StateError('boom');
      await cubit.startReceiving();
      await cubit.stopReceiving();
      expect(cubit.state.listener, InboxListenerStatus.off);
      expect(cubit.state.failureDetail, isNull);
    });

    test('accept delegates to repository and returns the new Note', () async {
      final share = _share('a', DateTime.utc(2026, 5, 9, 10));
      await repo.insert(share);
      await Future<void>.delayed(Duration.zero);

      final note = await cubit.accept('a');
      expect(repo.acceptedIds, ['a']);
      expect(note.id, share.note.id);
      expect(note.fromIdentityId, share.sender.id);
    });

    test('discard delegates to repository', () async {
      await repo.insert(_share('a', DateTime.utc(2026, 5, 9, 10)));
      await Future<void>.delayed(Duration.zero);
      await cubit.discard('a');
      expect(repo.discardedIds, ['a']);
    });

    test('listener events surface on uiEvents (not on state)', () async {
      final captured = <InboxListenerEvent>[];
      final sub = cubit.uiEvents.listen(captured.add);
      listener.emit(const DecodeRejected('signature_invalid'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(captured.whereType<DecodeRejected>(), hasLength(1));
    });
  });
}

class _ScriptedListener implements InboxListenerService {
  final StreamController<InboxListenerEvent> _events =
      StreamController<InboxListenerEvent>.broadcast();
  bool _on = false;

  Object? startError;
  bool stopped = false;

  void emit(InboxListenerEvent event) => _events.add(event);

  @override
  Stream<InboxListenerEvent> get events => _events.stream;

  @override
  bool get isReceiving => _on;

  @override
  Future<void> startReceiving() async {
    final err = startError;
    if (err != null) {
      // ignore: only_throw_errors
      throw err;
    }
    _on = true;
  }

  @override
  Future<void> stopReceiving() async {
    _on = false;
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

ReceivedShare _share(String id, DateTime receivedAt) {
  return ReceivedShare(
    shareId: id,
    receivedAt: receivedAt,
    sender: IncomingSender(
      id: 'sender-$id',
      displayName: 'Alice',
      publicKey: const <int>[1, 2, 3],
      signaturePalette: const <int>[0, 0, 0, 0],
      signaturePatternKey: null,
      signatureAccent: '✦',
      signatureTagline: '',
    ),
    note: IncomingNote(
      id: 'note-$id',
      title: 'Title',
      blocks: const <Map<String, dynamic>>[],
      tags: const <String>[],
      dateCreated: DateTime.utc(2026, 5, 9, 11),
      reminder: null,
      isPinned: false,
      overlay: const NotiThemeOverlay(
        surface: Color(0xFFEDE6D6),
        surfaceVariant: Color(0xFFE3DBC8),
        accent: Color(0xFF4A8A7F),
        onAccent: Color(0xFFEDE6D6),
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/$id',
  );
}

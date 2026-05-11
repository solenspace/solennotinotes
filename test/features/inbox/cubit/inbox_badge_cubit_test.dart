import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_badge_cubit.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

import '../../../repositories/received_inbox/fake_received_inbox_repository.dart';

void main() {
  group('InboxBadgeCubit', () {
    late FakeReceivedInboxRepository repo;
    late InboxBadgeCubit cubit;

    setUp(() {
      repo = FakeReceivedInboxRepository();
      cubit = InboxBadgeCubit(repository: repo)..start();
    });

    tearDown(() async {
      await cubit.close();
      await repo.dispose();
    });

    test('emits the running count of inbox entries', () async {
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 0);

      await repo.insert(_share('a'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 1);

      await repo.insert(_share('b'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 2);

      await repo.discard('a');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 1);
    });
  });
}

ReceivedShare _share(String id) {
  return ReceivedShare(
    shareId: id,
    receivedAt: DateTime.utc(2026, 5, 9, 12),
    sender: const IncomingSender(
      id: 'sender',
      displayName: 'Alice',
      publicKey: <int>[1, 2, 3],
      signaturePalette: <int>[0, 0, 0, 0],
      signaturePatternKey: null,
      signatureAccent: null,
      signatureTagline: '',
    ),
    note: IncomingNote(
      id: id,
      title: 't',
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

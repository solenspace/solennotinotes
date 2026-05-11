import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/hive_received_inbox_repository.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:path/path.dart' as p;

import '../../services/crypto/fake_keypair_service.dart';
import '../notes/fake_notes_repository.dart';

void main() {
  group('HiveReceivedInboxRepository', () {
    late Directory tempDocs;
    late Directory tempHive;
    late Box<dynamic> box;
    late FakeNotesRepository notes;
    late HiveReceivedInboxRepository repo;

    setUp(() async {
      tempDocs = Directory.systemTemp.createTempSync('received_inbox_docs_');
      tempHive = Directory.systemTemp.createTempSync('received_inbox_hive_');
      Hive.init(tempHive.path);
      box = await Hive.openBox<dynamic>('received_inbox_v1_test');
      notes = FakeNotesRepository();
      repo = HiveReceivedInboxRepository.withBox(
        box: box,
        notesRepository: notes,
        documentsRoot: tempDocs,
      );
      await repo.init();
    });

    tearDown(() async {
      await box.close();
      await Hive.deleteFromDisk();
      await notes.dispose();
      if (tempDocs.existsSync()) tempDocs.deleteSync(recursive: true);
      if (tempHive.existsSync()) tempHive.deleteSync(recursive: true);
    });

    test('insert + getAll round-trip preserves fields newest-first', () async {
      final s1 = _share(id: 's1', receivedAt: DateTime.utc(2026, 5, 9, 10));
      final s2 = _share(id: 's2', receivedAt: DateTime.utc(2026, 5, 9, 12));
      await repo.insert(s1);
      await repo.insert(s2);

      final all = await repo.getAll();
      expect(all.map((e) => e.shareId), ['s2', 's1']);
      expect(all.first.sender.displayName, 'Alice');
    });

    test('watchAll emits an initial snapshot reflecting the current box', () async {
      await repo.insert(_share(id: 's1'));
      final first = await repo.watchAll().first;
      expect(first.map((e) => e.shareId), ['s1']);
    });

    test('accept moves assets, rewrites block paths, and saves a Note', () async {
      final fixture = await _encodeRealShare(tempDocs);
      await repo.insert(fixture.share);

      final note = await repo.accept(fixture.share.shareId);

      expect(notes.savedNotes, hasLength(1));
      expect(note.id, fixture.share.note.id);
      expect(note.fromIdentityId, fixture.share.sender.id);
      expect(note.fromDisplayName, fixture.share.sender.displayName);
      expect(note.fromAccentGlyph, fixture.share.sender.signatureAccent);

      final imageBlock = note.blocks.firstWhere((b) => b['type'] == 'image');
      final audioBlock = note.blocks.firstWhere((b) => b['type'] == 'audio');
      final imagePath = imageBlock['path'] as String;
      final audioPath = audioBlock['path'] as String;
      expect(imagePath.contains(p.join('notes', note.id, 'images')), isTrue);
      expect(audioPath.contains(p.join('notes', note.id, 'audio')), isTrue);
      expect(File(imagePath).existsSync(), isTrue);
      expect(File(audioPath).existsSync(), isTrue);

      // Inbox cleared on disk + in Hive.
      expect(Directory(fixture.share.inboxRoot).existsSync(), isFalse);
      expect(await repo.getAll(), isEmpty);
    });

    test('discard removes the Hive entry and rm -rfs the inbox dir', () async {
      final fixture = await _encodeRealShare(tempDocs);
      await repo.insert(fixture.share);
      expect(Directory(fixture.share.inboxRoot).existsSync(), isTrue);

      await repo.discard(fixture.share.shareId);

      expect(await repo.getAll(), isEmpty);
      expect(Directory(fixture.share.inboxRoot).existsSync(), isFalse);
    });

    test('accept throws when the shareId is unknown', () async {
      expect(() => repo.accept('ghost'), throwsA(isA<StateError>()));
    });
  });
}

ReceivedShare _share({required String id, DateTime? receivedAt}) {
  return ReceivedShare(
    shareId: id,
    receivedAt: receivedAt ?? DateTime.utc(2026, 5, 9, 12),
    sender: const IncomingSender(
      id: 'sender-1',
      displayName: 'Alice',
      publicKey: <int>[1, 2, 3],
      signaturePalette: <int>[0xFF112233, 0xFF445566, 0xFF778899],
      signaturePatternKey: 'polygons',
      signatureAccent: '✦',
      signatureTagline: 'note from alice',
    ),
    note: IncomingNote(
      id: 'note-$id',
      title: 'Dinner ideas',
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
        onSurface: Color(0xFF1C1B1A),
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/nonexistent-$id',
  );
}

class _EncodedFixture {
  _EncodedFixture(this.share);
  final ReceivedShare share;
}

Future<_EncodedFixture> _encodeRealShare(Directory docsRoot) async {
  final imageBytes = List<int>.generate(2048, (i) => (i * 31) & 0xff);
  final audioBytes = List<int>.generate(4096, (i) => (i * 17) & 0xff);
  final srcDir = Directory(p.join(docsRoot.path, '_src'))..createSync(recursive: true);
  final imageFile = File(p.join(srcDir.path, 'src_image.jpg'))..writeAsBytesSync(imageBytes);
  final audioFile = File(p.join(srcDir.path, 'src_audio.m4a'))..writeAsBytesSync(audioBytes);

  final note = Note(
    {'family'},
    null,
    null,
    <Map<String, dynamic>>[],
    DateTime.utc(2026, 5, 9, 12),
    null,
    id: 'note-uuid',
    title: 'Sunday roast',
    content: '',
    dateCreated: DateTime.utc(2026, 5, 9, 11),
    colorBackground: const Color(0xFF1A1B1F),
    fontColor: const Color(0xFFEEEEEE),
    hasGradient: false,
    isPinned: true,
    blocks: <Map<String, dynamic>>[
      {'type': 'text', 'id': 'b-text', 'text': 'Hello there'},
      {'type': 'image', 'id': 'b-image', 'path': imageFile.path},
      {
        'type': 'audio',
        'id': 'b-audio',
        'path': audioFile.path,
        'durationMs': 1234,
        'amplitudePeaks': List<double>.filled(80, 0.5),
        'truncated': false,
      },
    ],
  );

  final identity = NotiIdentity(
    id: 'sender-uuid',
    displayName: 'Mateo',
    bornDate: DateTime.utc(1995, 1, 1),
    signaturePalette: const [
      Color(0xFF112233),
      Color(0xFF445566),
      Color(0xFF778899),
      Color(0xFFAABBCC),
    ],
    signaturePatternKey: 'waves',
    signatureAccent: '✦',
    signatureTagline: 'note from Mateo',
    publicKey: List<int>.generate(32, (i) => i),
  );
  final keypair = FakeKeypairService(publicKey: identity.publicKey);
  final encoder = ShareEncoder(keypair: keypair);
  final out = await encoder.encode(note: note, sender: identity);
  final decoder = ShareDecoder(keypair: keypair, documentsRoot: docsRoot);
  final result = await decoder.decode(out.bytes);
  final ok = result as DecodeOk;

  return _EncodedFixture(
    ReceivedShare(
      shareId: ok.share.shareId,
      receivedAt: DateTime.utc(2026, 5, 9, 12, 30),
      sender: ok.share.sender,
      note: ok.share.note,
      assets: ok.share.assets,
      inboxRoot: ok.share.inboxRoot,
    ),
  );
}

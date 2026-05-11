import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/notes/hive_notes_repository.dart';
import 'package:noti_notes_app/repositories/received_inbox/hive_received_inbox_repository.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_constants.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:path/path.dart' as p;

import '../test/services/crypto/fake_keypair_service.dart';
import '../test/services/share/in_memory_peer_pair.dart';

/// End-to-end harness for the share path (Spec 28).
///
/// Two simulated peers (an [InMemoryPeerPair]) exchange a `.noti` payload
/// through the real [ShareEncoder] / [ShareDecoder] and real
/// [HiveNotesRepository] / [HiveReceivedInboxRepository]; only the
/// transport is faked. Each scenario gets its own temp documents root and
/// temp Hive home so cross-test state cannot leak.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;
  late Directory tempHive;
  late Box<dynamic> notesBox;
  late Box<dynamic> inboxBox;
  late HiveNotesRepository receiverNotes;
  late HiveReceivedInboxRepository receiverInbox;
  late HiveNotesRepository senderNotes;
  late InMemoryPeerPair pair;

  setUp(() async {
    tempDocs = Directory.systemTemp.createTempSync('share_e2e_docs_');
    tempHive = Directory.systemTemp.createTempSync('share_e2e_hive_');
    Hive.init(tempHive.path);
    notesBox = await Hive.openBox<dynamic>('notes_v2_e2e');
    inboxBox = await Hive.openBox<dynamic>('received_inbox_v1_e2e');

    senderNotes = HiveNotesRepository.withBox(box: notesBox);
    receiverNotes = HiveNotesRepository.withBox(
      box: await Hive.openBox<dynamic>('notes_v2_receiver_e2e'),
    );
    receiverInbox = HiveReceivedInboxRepository.withBox(
      box: inboxBox,
      notesRepository: receiverNotes,
      documentsRoot: tempDocs,
    );
    await receiverInbox.init();

    pair = InMemoryPeerPair();
    await pair.a.start(role: PeerRole.both, displayName: 'alex');
    await pair.b.start(role: PeerRole.both, displayName: 'bob');
  });

  tearDown(() async {
    await pair.dispose();
    await Hive.close();
    await Hive.deleteFromDisk();
    if (tempDocs.existsSync()) tempDocs.deleteSync(recursive: true);
    if (tempHive.existsSync()) tempHive.deleteSync(recursive: true);
  });

  testWidgets('happy path — styled note + image + audio round-trips end-to-end', (tester) async {
    final fixture = await _buildFixture(tempDocs);
    final encoder = ShareEncoder(keypair: fixture.senderKeypair);
    final decoder = ShareDecoder(keypair: fixture.receiverKeypair, documentsRoot: tempDocs);

    await senderNotes.save(fixture.note);

    final out = await encoder.encode(note: fixture.note, sender: fixture.identity);
    final delivered = pair.b.payloadStream.first;
    await pair.a.sendBytes(pair.bPeerId, out.bytes);
    final inbound = await delivered.timeout(const Duration(seconds: 2));

    final result = await decoder.decode(inbound.bytes);
    expect(result, isA<DecodeOk>());
    final ok = result as DecodeOk;
    await receiverInbox.insert(
      ReceivedShare(
        shareId: ok.share.shareId,
        receivedAt: DateTime.utc(2026, 5, 11, 12),
        sender: ok.share.sender,
        note: ok.share.note,
        assets: ok.share.assets,
        inboxRoot: ok.share.inboxRoot,
      ),
    );

    final pending = await receiverInbox.getAll();
    expect(pending, hasLength(1));
    expect(pending.first.note.title, fixture.note.title);

    final accepted = await receiverInbox.accept(pending.first.shareId);
    expect(accepted.id, fixture.note.id);
    expect(accepted.title, fixture.note.title);
    expect(accepted.colorBackground, fixture.note.colorBackground);
    expect(accepted.patternImage, fixture.note.patternImage);
    expect(accepted.blocks.length, fixture.note.blocks.length);
    expect(accepted.fromIdentityId, fixture.identity.id);
    expect(accepted.fromDisplayName, fixture.identity.displayName);

    final imageBlock = accepted.blocks.firstWhere((b) => b['type'] == 'image');
    final audioBlock = accepted.blocks.firstWhere((b) => b['type'] == 'audio');
    expect(File(imageBlock['path'] as String).existsSync(), isTrue);
    expect(File(audioBlock['path'] as String).existsSync(), isTrue);

    // Inbox is drained after accept; the on-disk inbox dir is rm -rf'd.
    expect(await receiverInbox.getAll(), isEmpty);
    expect(Directory(ok.share.inboxRoot).existsSync(), isFalse);
  });

  testWidgets('cancel mid-transfer — cancelTransfer logged; receiver inbox empty', (tester) async {
    final fixture = await _buildFixture(tempDocs);
    final encoder = ShareEncoder(keypair: fixture.senderKeypair);
    await senderNotes.save(fixture.note);

    final out = await encoder.encode(note: fixture.note, sender: fixture.identity);
    final transferId = await pair.a.sendBytes(pair.bPeerId, out.bytes);
    await pair.a.cancelTransfer(transferId);

    // Real cancel semantics: the sender signals abort to the receiver-side
    // listener, which drops in-flight bytes rather than decoding them. The
    // contract exercised here is the [FakePeerService] action log — sender
    // called sendBytes then cancelTransfer with the same transfer id — and
    // the receiver never running decode → no inbox entry.
    expect(pair.a.actionLog, contains('sendBytes:${pair.bPeerId}:${out.bytes.length}:$transferId'));
    expect(pair.a.actionLog, contains('cancelTransfer:$transferId'));
    expect(await receiverInbox.getAll(), isEmpty);
  });

  testWidgets('tampered bytes — DecodeSignatureInvalid; inbox empty', (tester) async {
    final fixture = await _buildFixture(tempDocs);
    final encoder = ShareEncoder(keypair: fixture.senderKeypair);
    final decoder = ShareDecoder(keypair: fixture.receiverKeypair, documentsRoot: tempDocs);

    final out = await encoder.encode(note: fixture.note, sender: fixture.identity);
    final tampered = _replaceArchiveEntry(
      out.bytes,
      shareSignatureEntry,
      List<int>.filled(64, 0xff),
    );

    final delivered = pair.b.payloadStream.first;
    await pair.a.sendBytes(pair.bPeerId, tampered);
    final inbound = await delivered.timeout(const Duration(seconds: 2));
    final result = await decoder.decode(inbound.bytes);

    expect(result, isA<DecodeSignatureInvalid>());
    // Receiver must not write anything to the inbox on a verification failure.
    expect(await receiverInbox.getAll(), isEmpty);
  });

  testWidgets('oversize payload — encoder throws PayloadTooLarge; nothing leaves', (tester) async {
    final fixture = await _buildFixture(
      tempDocs,
      audioBytes: List<int>.filled(shareMaxPayloadBytes + 1, 7),
    );
    final encoder = ShareEncoder(keypair: fixture.senderKeypair);

    await expectLater(
      encoder.encode(note: fixture.note, sender: fixture.identity),
      throwsA(isA<PayloadTooLarge>()),
    );

    // Transport was never called; receiver inbox empty.
    expect(pair.a.actionLog.where((s) => s.startsWith('sendBytes')), isEmpty);
    expect(await receiverInbox.getAll(), isEmpty);
  });
}

class _Fixture {
  _Fixture({
    required this.note,
    required this.identity,
    required this.senderKeypair,
    required this.receiverKeypair,
  });

  final Note note;
  final NotiIdentity identity;
  final FakeKeypairService senderKeypair;
  final FakeKeypairService receiverKeypair;
}

/// Builds a Note with one image + one audio block whose asset files live
/// inside [tempDocs]. The image and audio bytes are synthesized (no
/// committed binary fixtures); the codec only validates size + sha256, not
/// playability, so a deterministic byte buffer is sufficient.
Future<_Fixture> _buildFixture(
  Directory tempDocs, {
  List<int>? audioBytes,
}) async {
  final srcDir = Directory(p.join(tempDocs.path, '_src'))..createSync(recursive: true);
  final imagePayload = List<int>.generate(1024 * 1024, (i) => (i * 31) & 0xff); // ~1 MB
  final audioPayload =
      audioBytes ?? List<int>.generate(200 * 1024, (i) => (i * 17) & 0xff); // ~200 KB
  final imageFile = File(p.join(srcDir.path, 'mini_image.jpg'))..writeAsBytesSync(imagePayload);
  final audioFile = File(p.join(srcDir.path, 'mini_audio.m4a'))..writeAsBytesSync(audioPayload);

  final note = Note(
    {'family', 'recipes'},
    null,
    'waves', // patternImage — round-trips through overlay.patternKey
    <Map<String, dynamic>>[],
    null,
    null,
    id: 'note-e2e',
    title: 'E2E share — note from alex',
    content: '',
    dateCreated: DateTime.utc(2026, 5, 11, 10),
    colorBackground: const Color(0xFF1F2620),
    fontColor: const Color(0xFFEDE6D6),
    hasGradient: false,
    isPinned: true,
    blocks: <Map<String, dynamic>>[
      {'type': 'text', 'id': 'b-text', 'text': 'Shared from alex to bob'},
      {'type': 'image', 'id': 'b-image', 'path': imageFile.path},
      {
        'type': 'audio',
        'id': 'b-audio',
        'path': audioFile.path,
        'durationMs': 2400,
        'amplitudePeaks': List<double>.filled(80, 0.5),
        'truncated': false,
      },
    ],
  );

  // Same 32-byte key shape ShareEncoder embeds in the manifest. The
  // receiver's FakeKeypairService verifies using the publicKey lifted from
  // the manifest, so its own _publicKey only matters for sign() (unused on
  // the receiver side here).
  final senderPubKey = List<int>.generate(32, (i) => i);
  final identity = NotiIdentity(
    id: 'sender-alex',
    displayName: 'alex',
    bornDate: DateTime.utc(1995, 1, 1),
    signaturePalette: const [
      Color(0xFF1F2620),
      Color(0xFF2A332C),
      Color(0xFF8FA66F),
      Color(0xFF111712),
    ],
    signaturePatternKey: 'waves',
    signatureAccent: '✦',
    signatureTagline: 'note from alex',
    publicKey: senderPubKey,
  );

  return _Fixture(
    note: note,
    identity: identity,
    senderKeypair: FakeKeypairService(publicKey: senderPubKey),
    receiverKeypair: FakeKeypairService(publicKey: List<int>.generate(32, (i) => i + 100)),
  );
}

List<int> _replaceArchiveEntry(
  List<int> zipBytes,
  String entryName,
  List<int> newBytes,
) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final rebuilt = Archive();
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final bytes = f.name == entryName ? newBytes : f.content as List<int>;
    rebuilt.addFile(ArchiveFile(f.name, bytes.length, bytes));
  }
  return ZipEncoder().encode(rebuilt);
}

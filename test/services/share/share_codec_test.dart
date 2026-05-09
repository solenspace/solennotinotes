import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_constants.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:path/path.dart' as p;

import '../crypto/fake_keypair_service.dart';

void main() {
  group('ShareCodec', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('share_codec_test_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('round trip encodes, decodes, and verifies', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );

      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);
      final result = await decoder.decode(out.bytes);

      expect(result, isA<DecodeOk>());
      final ok = result as DecodeOk;
      final share = ok.share;

      expect(share.shareId, out.shareId);
      expect(share.note.id, fixture.note.id);
      expect(share.note.title, fixture.note.title);
      expect(share.note.tags, fixture.note.tags.toList());
      expect(share.note.isPinned, fixture.note.isPinned);
      expect(share.note.blocks.length, fixture.note.blocks.length);
      expect(share.sender.id, fixture.identity.id);
      expect(share.sender.displayName, fixture.identity.displayName);
      expect(share.sender.publicKey, fixture.identity.publicKey);
      expect(share.assets, hasLength(2));

      for (final asset in share.assets) {
        final extracted = File(p.join(share.inboxRoot, asset.pathInArchive));
        expect(extracted.existsSync(), isTrue, reason: 'asset ${asset.id} should be extracted');
        expect(extracted.lengthSync(), asset.sizeBytes);
      }
    });

    test('tampered signature fails verification', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final tampered = _replaceArchiveEntry(
        out.bytes,
        shareSignatureEntry,
        List<int>.filled(64, 0xff),
      );

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      expect(await decoder.decode(tampered), isA<DecodeSignatureInvalid>());
    });

    test('tampered manifest fails verification', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final manifestBytes = _readArchiveEntry(out.bytes, shareManifestEntry);
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      (manifest['note'] as Map<String, dynamic>)['title'] = 'Forged';
      final replaced = _replaceArchiveEntry(
        out.bytes,
        shareManifestEntry,
        utf8.encode(jsonEncode(manifest)),
      );

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      expect(await decoder.decode(replaced), isA<DecodeSignatureInvalid>());
    });

    test('tampered asset bytes fail verification', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final manifestBytes = _readArchiveEntry(out.bytes, shareManifestEntry);
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      final firstAsset = (manifest['assets'] as List).first as Map<String, dynamic>;
      final assetPath = firstAsset['path_in_archive'] as String;
      final original = _readArchiveEntry(out.bytes, assetPath);
      final flipped = List<int>.from(original)..[0] ^= 0x01;
      final replaced = _replaceArchiveEntry(out.bytes, assetPath, flipped);

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      expect(await decoder.decode(replaced), isA<DecodeSignatureInvalid>());
    });

    test('encode rejects oversize payload', () async {
      final fixture = await _buildFixture(
        tempRoot,
        audioBytes: List<int>.filled(shareMaxPayloadBytes + 1, 7),
      );
      final encoder = ShareEncoder(keypair: fixture.keypair);
      expect(
        () => encoder.encode(note: fixture.note, sender: fixture.identity),
        throwsA(isA<PayloadTooLarge>()),
      );
    });

    test('decode rejects oversize payload before parsing', () async {
      final fixture = await _buildFixture(tempRoot);
      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      final tooBig = List<int>.filled(shareMaxPayloadBytes + 1, 0);
      final result = await decoder.decode(tooBig);
      expect(result, isA<DecodeSizeExceeded>());
    });

    test('unsupported version is reported', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final manifestBytes = _readArchiveEntry(out.bytes, shareManifestEntry);
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      manifest['format_version'] = 2;
      final replaced = _replaceArchiveEntry(
        out.bytes,
        shareManifestEntry,
        utf8.encode(jsonEncode(manifest)),
      );

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      final result = await decoder.decode(replaced);
      expect(result, isA<DecodeUnsupportedVersion>());
      expect((result as DecodeUnsupportedVersion).version, 2);
    });

    test('missing manifest is malformed', () async {
      final empty = ZipEncoder().encode(Archive());
      final decoder = ShareDecoder(
        keypair: FakeKeypairService(),
        documentsRoot: tempRoot,
      );
      final result = await decoder.decode(empty);
      expect(result, isA<DecodeMalformed>());
    });

    test('missing required field is malformed', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final manifestBytes = _readArchiveEntry(out.bytes, shareManifestEntry);
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      (manifest['sender'] as Map<String, dynamic>).remove('id');
      final replaced = _replaceArchiveEntry(
        out.bytes,
        shareManifestEntry,
        utf8.encode(jsonEncode(manifest)),
      );

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      expect(await decoder.decode(replaced), isA<DecodeMalformed>());
    });

    test('rejects manifest with path-traversal asset path', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);

      final manifestBytes = _readArchiveEntry(out.bytes, shareManifestEntry);
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      final assets = (manifest['assets'] as List).cast<Map<String, dynamic>>();
      assets.first['path_in_archive'] = '../../escape.dat';
      final replaced = _replaceArchiveEntry(
        out.bytes,
        shareManifestEntry,
        utf8.encode(jsonEncode(manifest)),
      );

      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      final result = await decoder.decode(replaced);
      expect(result, isA<DecodeMalformed>());
      expect((result as DecodeMalformed).reason, contains('unsafe'));
    });

    test('rejects archive whose decompressed total exceeds the cap', () async {
      // Build a one-entry archive whose decompressed size exceeds the cap.
      // Compresses to a tiny zip thanks to deflate of a constant byte.
      final huge = List<int>.filled(shareMaxPayloadBytes + 1024, 0);
      final archive = Archive()..addFile(ArchiveFile(shareManifestEntry, huge.length, huge));
      final bombBytes = ZipEncoder().encode(archive);

      final decoder = ShareDecoder(
        keypair: FakeKeypairService(),
        documentsRoot: tempRoot,
      );
      expect(await decoder.decode(bombBytes), isA<DecodeSizeExceeded>());
    });

    test('inbox extraction writes byte-identical assets', () async {
      final fixture = await _buildFixture(tempRoot);
      final encoder = ShareEncoder(keypair: fixture.keypair);
      final decoder = ShareDecoder(
        keypair: fixture.keypair,
        documentsRoot: tempRoot,
      );
      final out = await encoder.encode(note: fixture.note, sender: fixture.identity);
      final ok = (await decoder.decode(out.bytes)) as DecodeOk;

      final inbox = Directory(p.join(tempRoot.path, 'inbox', ok.share.shareId));
      expect(inbox.existsSync(), isTrue);

      final imageAsset = ok.share.assets.firstWhere((a) => a.kind == ShareAssetKind.image);
      final extractedImage = File(p.join(inbox.path, imageAsset.pathInArchive));
      expect(await extractedImage.readAsBytes(), fixture.imageBytes);

      final audioAsset = ok.share.assets.firstWhere((a) => a.kind == ShareAssetKind.audio);
      final extractedAudio = File(p.join(inbox.path, audioAsset.pathInArchive));
      expect(await extractedAudio.readAsBytes(), fixture.audioBytes);
    });
  });
}

class _Fixture {
  _Fixture({
    required this.note,
    required this.identity,
    required this.keypair,
    required this.imageBytes,
    required this.audioBytes,
  });
  final Note note;
  final NotiIdentity identity;
  final FakeKeypairService keypair;
  final List<int> imageBytes;
  final List<int> audioBytes;
}

Future<_Fixture> _buildFixture(
  Directory root, {
  List<int>? audioBytes,
}) async {
  final imageBytes = List<int>.generate(2048, (i) => (i * 31) & 0xff);
  final audioPayload = audioBytes ?? List<int>.generate(4096, (i) => (i * 17) & 0xff);

  final imageFile = File(p.join(root.path, 'src_image.jpg'))..writeAsBytesSync(imageBytes);
  final audioFile = File(p.join(root.path, 'src_audio.m4a'))..writeAsBytesSync(audioPayload);

  final note = Note(
    {'family', 'recipes'},
    null,
    null,
    <Map<String, dynamic>>[],
    DateTime.utc(2026, 5, 9, 12, 0),
    null,
    id: 'note-uuid',
    title: 'Sunday roast',
    content: '',
    dateCreated: DateTime.utc(2026, 5, 9, 11, 0),
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
    signaturePalette: const [Color(0xFF112233), Color(0xFF445566)],
    signaturePatternKey: 'waves',
    signatureAccent: '✦',
    signatureTagline: 'note from Mateo',
    publicKey: List<int>.generate(32, (i) => i),
  );

  final keypair = FakeKeypairService(publicKey: identity.publicKey);
  return _Fixture(
    note: note,
    identity: identity,
    keypair: keypair,
    imageBytes: imageBytes,
    audioBytes: audioPayload,
  );
}

List<int> _readArchiveEntry(List<int> zipBytes, String entryName) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final file = archive.files.firstWhere((f) => f.name == entryName);
  return file.content as List<int>;
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

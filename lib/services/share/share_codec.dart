import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/crypto/keypair_service.dart';
import 'package:noti_notes_app/services/share/share_constants.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Encodes a [Note] + sender [NotiIdentity] into the wire-format `.noti`
/// archive defined in Spec 23.
///
/// Output is a self-contained ZIP: `manifest.json` (canonicalized,
/// sorted-keys), `signature.bin` (Ed25519 over manifest bytes ++ asset
/// bytes in declared order), and one entry per embedded image / audio
/// asset under `assets/<kind>s/<assetId>.<ext>`.
class ShareEncoder {
  ShareEncoder({required KeypairService keypair, Uuid? uuid})
      : _keypair = keypair,
        _uuid = uuid ?? const Uuid();

  final KeypairService _keypair;
  final Uuid _uuid;

  Future<OutgoingShare> encode({
    required Note note,
    required NotiIdentity sender,
  }) async {
    final shareId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();

    final assets = <_PackedAsset>[];
    var totalAssetBytes = 0;
    for (final block in note.blocks) {
      final packed = await _packBlockAsset(block);
      if (packed == null) continue;
      assets.add(packed);
      totalAssetBytes += packed.bytes.length;
      if (totalAssetBytes > shareMaxPayloadBytes) {
        throw PayloadTooLarge(
          actual: totalAssetBytes,
          cap: shareMaxPayloadBytes,
        );
      }
    }

    // Round-trip through JSON before signing so the encoder canonicalizes
    // over the same Dart shapes the decoder will see (List<double> →
    // List<num>, etc.). Without this, blocks like AudioBlock.amplitudePeaks
    // would canonicalize differently on the two sides and signatures would
    // not verify.
    final rawManifest = <String, dynamic>{
      'format_version': shareFormatVersion,
      'share_id': shareId,
      'created_at': createdAt.toIso8601String(),
      'sender': _senderJson(sender),
      'note': _noteJson(note),
      'assets': assets.map((a) => a.manifestEntry).toList(growable: false),
    };
    final manifest = jsonDecode(jsonEncode(rawManifest)) as Map<String, dynamic>;

    final manifestBytes = _canonicalJsonBytes(manifest);
    final signingInput = _concatForSigning(manifestBytes, assets);
    if (signingInput.length > shareMaxPayloadBytes) {
      throw PayloadTooLarge(
        actual: signingInput.length,
        cap: shareMaxPayloadBytes,
      );
    }

    final signature = await _keypair.sign(signingInput);

    final zipped = _zip(manifestBytes, signature, assets);
    if (zipped.length > shareMaxPayloadBytes) {
      throw PayloadTooLarge(
        actual: zipped.length,
        cap: shareMaxPayloadBytes,
      );
    }

    return OutgoingShare(bytes: zipped, shareId: shareId);
  }

  Future<_PackedAsset?> _packBlockAsset(Map<String, dynamic> block) async {
    final type = block['type'] as String?;
    final id = block['id'] as String?;
    final path = block['path'] as String?;
    if (id == null || path == null || path.isEmpty) return null;

    final ShareAssetKind kind;
    final String archiveDir;
    final String extension;
    switch (type) {
      case 'image':
        kind = ShareAssetKind.image;
        archiveDir = shareImagesDir;
        extension = _extensionOrDefault(path, 'jpg');
      case 'audio':
        kind = ShareAssetKind.audio;
        archiveDir = shareAudioDir;
        extension = _extensionOrDefault(path, 'm4a');
      default:
        return null;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Asset file missing for block $id: $path');
    }
    final bytes = await file.readAsBytes();
    final pathInArchive = '$archiveDir/$id.$extension';
    return _PackedAsset(
      id: id,
      kind: kind,
      pathInArchive: pathInArchive,
      bytes: bytes,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  Map<String, dynamic> _senderJson(NotiIdentity sender) {
    return <String, dynamic>{
      'id': sender.id,
      'display_name': sender.displayName,
      'public_key': base64Encode(sender.publicKey),
      'signature_palette': sender.signaturePalette.map((c) => c.toARGB32()).toList(growable: false),
      'signature_pattern_key': sender.signaturePatternKey,
      'signature_accent': sender.signatureAccent,
      'signature_tagline': sender.signatureTagline,
    };
  }

  Map<String, dynamic> _noteJson(Note note) {
    final overlay = note.toOverlay();
    return <String, dynamic>{
      'id': note.id,
      'title': note.title,
      'blocks': note.blocks,
      'tags': note.tags.toList(growable: false),
      'date_created': note.dateCreated.toIso8601String(),
      'reminder': note.reminder?.toIso8601String(),
      'is_pinned': note.isPinned,
      'overlay': <String, dynamic>{
        'surface': overlay.surface.toARGB32(),
        'surface_variant': overlay.surfaceVariant.toARGB32(),
        'accent': overlay.accent.toARGB32(),
        'on_accent': overlay.onAccent.toARGB32(),
        'on_surface': overlay.onSurface?.toARGB32(),
        'pattern_key': overlay.patternKey?.name,
      },
    };
  }
}

/// Decodes a `.noti` archive back into a verified [IncomingShare] with
/// assets extracted under `<documentsRoot>/inbox/<share_id>/`. Validation
/// order (size → version → manifest schema → signature → asset hashes)
/// matches Spec 23 so cheaper checks fail first and never reveal manifest
/// contents on tampered payloads.
class ShareDecoder {
  ShareDecoder({
    required KeypairService keypair,
    required Directory documentsRoot,
  })  : _keypair = keypair,
        _documentsRoot = documentsRoot;

  final KeypairService _keypair;
  final Directory _documentsRoot;

  Future<DecodeResult> decode(List<int> bytes) async {
    if (bytes.length > shareMaxPayloadBytes) {
      return DecodeSizeExceeded(actual: bytes.length, cap: shareMaxPayloadBytes);
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (e) {
      return DecodeMalformed('archive: $e');
    }

    // Reject zip-bomb-shaped archives where the sum of decompressed entry
    // sizes exceeds the payload cap, before reading any `.content`.
    var decompressedTotal = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      decompressedTotal += f.size;
      if (decompressedTotal > shareMaxPayloadBytes) {
        return DecodeSizeExceeded(actual: decompressedTotal, cap: shareMaxPayloadBytes);
      }
    }

    final entries = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };

    final manifestFile = entries[shareManifestEntry];
    final signatureFile = entries[shareSignatureEntry];
    if (manifestFile == null) return const DecodeMalformed('missing manifest.json');
    if (signatureFile == null) return const DecodeMalformed('missing signature.bin');

    final manifestBytes = manifestFile.content as List<int>;
    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    } catch (e) {
      return DecodeMalformed('manifest json: $e');
    }

    final version = manifest['format_version'];
    if (version is! int) return const DecodeMalformed('format_version not int');
    if (version != shareFormatVersion) return DecodeUnsupportedVersion(version);

    final parsed = _parseManifest(manifest);
    if (parsed is _ParseFailure) return DecodeMalformed(parsed.reason);
    parsed as _ParseOk;

    final assetEntries = <_AssetEntry>[];
    final seenPaths = <String>{};
    for (final asset in parsed.assets) {
      if (!_isSafeAssetPath(asset.pathInArchive)) {
        return DecodeMalformed('asset path unsafe: ${asset.pathInArchive}');
      }
      if (!seenPaths.add(asset.pathInArchive)) {
        return DecodeMalformed('asset path duplicated: ${asset.pathInArchive}');
      }
      final entry = entries[asset.pathInArchive];
      if (entry == null) {
        return DecodeMalformed('asset entry missing: ${asset.pathInArchive}');
      }
      final assetBytes = entry.content as List<int>;
      if (assetBytes.length != asset.sizeBytes) {
        return DecodeMalformed('asset size mismatch: ${asset.id}');
      }
      assetEntries.add(_AssetEntry(asset: asset, bytes: assetBytes));
    }

    final canonicalManifestBytes = _canonicalJsonBytes(manifest);
    final signingInput = BytesBuilder(copy: false)..add(canonicalManifestBytes);
    for (final e in assetEntries) {
      signingInput.add(e.bytes);
    }

    final signatureBytes = signatureFile.content as List<int>;
    final senderPublicKey = base64Decode(parsed.senderPublicKeyB64);
    final ok = await _keypair.verify(
      bytes: signingInput.toBytes(),
      signature: signatureBytes,
      publicKey: senderPublicKey,
    );
    if (!ok) return const DecodeSignatureInvalid();

    for (final e in assetEntries) {
      final actual = sha256.convert(e.bytes).toString();
      if (actual != e.asset.sha256) {
        return DecodeMalformed('asset sha256 mismatch: ${e.asset.id}');
      }
    }

    final inboxRoot = Directory(p.join(_documentsRoot.path, 'inbox', parsed.shareId));
    if (await inboxRoot.exists()) {
      await inboxRoot.delete(recursive: true);
    }
    await inboxRoot.create(recursive: true);
    try {
      for (final e in assetEntries) {
        final file = File(p.join(inboxRoot.path, e.asset.pathInArchive));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(e.bytes, flush: true);
      }
    } catch (e) {
      if (await inboxRoot.exists()) {
        await inboxRoot.delete(recursive: true);
      }
      return DecodeMalformed('extract: $e');
    }

    return DecodeOk(
      IncomingShare(
        shareId: parsed.shareId,
        createdAt: parsed.createdAt,
        sender: IncomingSender(
          id: parsed.senderId,
          displayName: parsed.senderDisplayName,
          publicKey: senderPublicKey,
          signaturePalette: parsed.senderPalette,
          signaturePatternKey: parsed.senderPatternKey,
          signatureAccent: parsed.senderAccent,
          signatureTagline: parsed.senderTagline,
        ),
        note: parsed.note,
        assets: parsed.assets,
        inboxRoot: inboxRoot.path,
      ),
    );
  }

  _ParseResult _parseManifest(Map<String, dynamic> manifest) {
    try {
      final shareId = manifest['share_id'] as String;
      final createdAt = DateTime.parse(manifest['created_at'] as String);

      final sender = manifest['sender'] as Map<String, dynamic>;
      final senderId = sender['id'] as String;
      final senderDisplayName = sender['display_name'] as String;
      final senderPublicKeyB64 = sender['public_key'] as String;
      final senderPalette =
          (sender['signature_palette'] as List).cast<int>().toList(growable: false);
      final senderPatternKey = sender['signature_pattern_key'] as String?;
      final senderAccent = sender['signature_accent'] as String?;
      final senderTagline = (sender['signature_tagline'] as String?) ?? '';

      if (shareId.isEmpty) return const _ParseFailure('share_id empty');
      if (senderId.isEmpty) return const _ParseFailure('sender.id empty');
      if (senderDisplayName.isEmpty) {
        return const _ParseFailure('sender.display_name empty');
      }
      if (senderPublicKeyB64.isEmpty) {
        return const _ParseFailure('sender.public_key empty');
      }

      final note = manifest['note'] as Map<String, dynamic>;
      final overlayJson = note['overlay'] as Map<String, dynamic>;
      final overlay = NotiThemeOverlay(
        surface: _color(overlayJson['surface']),
        surfaceVariant: _color(overlayJson['surface_variant']),
        accent: _color(overlayJson['accent']),
        onAccent: _color(overlayJson['on_accent']),
        onSurface: _nullableColor(overlayJson['on_surface']),
        patternKey: NotiPatternKey.fromString(overlayJson['pattern_key'] as String?),
        fromIdentityId: senderId,
      );

      final reminderRaw = note['reminder'];
      final incomingNote = IncomingNote(
        id: note['id'] as String,
        title: note['title'] as String,
        blocks: (note['blocks'] as List)
            .cast<Map<dynamic, dynamic>>()
            .map((m) => m.cast<String, dynamic>())
            .toList(growable: false),
        tags: (note['tags'] as List).cast<String>().toList(growable: false),
        dateCreated: DateTime.parse(note['date_created'] as String),
        reminder: reminderRaw is String ? DateTime.parse(reminderRaw) : null,
        isPinned: note['is_pinned'] as bool,
        overlay: overlay,
      );

      final assets = <IncomingAsset>[];
      for (final raw in manifest['assets'] as List) {
        final m = (raw as Map).cast<String, dynamic>();
        final kind = ShareAssetKindWire.fromWire(m['kind'] as String?);
        if (kind == null) {
          return _ParseFailure('asset kind unknown: ${m['kind']}');
        }
        assets.add(
          IncomingAsset(
            id: m['id'] as String,
            kind: kind,
            pathInArchive: m['path_in_archive'] as String,
            sizeBytes: m['size_bytes'] as int,
            sha256: m['sha256'] as String,
          ),
        );
      }

      return _ParseOk(
        shareId: shareId,
        createdAt: createdAt,
        senderId: senderId,
        senderDisplayName: senderDisplayName,
        senderPublicKeyB64: senderPublicKeyB64,
        senderPalette: senderPalette,
        senderPatternKey: senderPatternKey,
        senderAccent: senderAccent,
        senderTagline: senderTagline,
        note: incomingNote,
        assets: assets,
      );
    } on TypeError catch (e) {
      return _ParseFailure('field type: ${e.toString()}');
    } on FormatException catch (e) {
      return _ParseFailure('field format: ${e.message}');
    } on ArgumentError catch (e) {
      return _ParseFailure('field arg: ${e.message}');
    }
  }
}

class _PackedAsset {
  _PackedAsset({
    required this.id,
    required this.kind,
    required this.pathInArchive,
    required this.bytes,
    required this.sha256,
  });

  final String id;
  final ShareAssetKind kind;
  final String pathInArchive;
  final List<int> bytes;
  final String sha256;

  Map<String, dynamic> get manifestEntry => <String, dynamic>{
        'id': id,
        'kind': kind.wireName,
        'path_in_archive': pathInArchive,
        'size_bytes': bytes.length,
        'sha256': sha256,
      };
}

class _AssetEntry {
  const _AssetEntry({required this.asset, required this.bytes});
  final IncomingAsset asset;
  final List<int> bytes;
}

sealed class _ParseResult {
  const _ParseResult();
}

class _ParseOk extends _ParseResult {
  const _ParseOk({
    required this.shareId,
    required this.createdAt,
    required this.senderId,
    required this.senderDisplayName,
    required this.senderPublicKeyB64,
    required this.senderPalette,
    required this.senderPatternKey,
    required this.senderAccent,
    required this.senderTagline,
    required this.note,
    required this.assets,
  });

  final String shareId;
  final DateTime createdAt;
  final String senderId;
  final String senderDisplayName;
  final String senderPublicKeyB64;
  final List<int> senderPalette;
  final String? senderPatternKey;
  final String? senderAccent;
  final String senderTagline;
  final IncomingNote note;
  final List<IncomingAsset> assets;
}

class _ParseFailure extends _ParseResult {
  const _ParseFailure(this.reason);
  final String reason;
}

/// Recursively-sorted JSON encoding for the bytes that get signed and
/// re-derived on the receiver. Map insertion order is unstable across
/// Hive round-trips; sorting by key before encode is what makes the
/// signature reproducible.
Uint8List _canonicalJsonBytes(Object? value) {
  final buf = StringBuffer();
  _writeCanonical(buf, value);
  return Uint8List.fromList(utf8.encode(buf.toString()));
}

void _writeCanonical(StringBuffer buf, Object? value) {
  if (value == null) {
    buf.write('null');
    return;
  }
  if (value is bool || value is num) {
    buf.write(jsonEncode(value));
    return;
  }
  if (value is String) {
    buf.write(jsonEncode(value));
    return;
  }
  if (value is List) {
    buf.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i != 0) buf.write(',');
      _writeCanonical(buf, value[i]);
    }
    buf.write(']');
    return;
  }
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    buf.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i != 0) buf.write(',');
      buf.write(jsonEncode(keys[i]));
      buf.write(':');
      _writeCanonical(buf, value[keys[i]]);
    }
    buf.write('}');
    return;
  }
  throw ArgumentError('Cannot canonicalize ${value.runtimeType}');
}

Uint8List _concatForSigning(Uint8List manifestBytes, List<_PackedAsset> assets) {
  final builder = BytesBuilder(copy: false)..add(manifestBytes);
  for (final a in assets) {
    builder.add(a.bytes);
  }
  return builder.toBytes();
}

List<int> _zip(
  Uint8List manifestBytes,
  List<int> signatureBytes,
  List<_PackedAsset> assets,
) {
  final archive = Archive()
    ..addFile(ArchiveFile(shareManifestEntry, manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile(shareSignatureEntry, signatureBytes.length, signatureBytes));
  for (final a in assets) {
    archive.addFile(ArchiveFile(a.pathInArchive, a.bytes.length, a.bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return encoded;
}

String _extensionOrDefault(String path, String fallback) {
  final ext = p.extension(path);
  if (ext.isEmpty) return fallback;
  return ext.startsWith('.') ? ext.substring(1) : ext;
}

/// Rejects path-traversal attempts in `assets[].path_in_archive`. The
/// signature only proves a sender authored the manifest — a malicious
/// sender can still craft an entry like `../../etc/foo`. Allowed shapes
/// are `assets/<dir>/<file>` with no `..` segments and no absolute roots.
bool _isSafeAssetPath(String pathInArchive) {
  if (pathInArchive.isEmpty) return false;
  if (pathInArchive.contains('\\')) return false;
  if (p.isAbsolute(pathInArchive)) return false;
  final segments = p.posix.split(pathInArchive);
  if (segments.any((s) => s == '..' || s == '.')) return false;
  if (segments.length < 3 || segments[0] != 'assets') return false;
  const allowedDirs = {'images', 'audio', 'transcripts'};
  return allowedDirs.contains(segments[1]);
}

Color _color(Object? value) {
  if (value is! int) {
    throw FormatException('color int expected, got ${value.runtimeType}');
  }
  return Color(value);
}

Color? _nullableColor(Object? value) => value == null ? null : _color(value);

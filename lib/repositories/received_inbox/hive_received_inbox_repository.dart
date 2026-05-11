import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Hive-backed implementation of [ReceivedInboxRepository]. Stores each
/// entry as a JSON-encoded string keyed by `share_id` in the
/// `received_inbox_v1` box. Asset bytes are not stored here — they live
/// on disk under `<documents>/inbox/<share_id>/` (written there by
/// [ShareDecoder]) and are either moved on accept or rm -rf'd on
/// discard.
class HiveReceivedInboxRepository implements ReceivedInboxRepository {
  HiveReceivedInboxRepository({
    required NotesRepository notesRepository,
    Directory? documentsRoot,
  })  : _notes = notesRepository,
        _documentsRootOverride = documentsRoot;

  @visibleForTesting
  HiveReceivedInboxRepository.withBox({
    required Box<dynamic> box,
    required NotesRepository notesRepository,
    required Directory documentsRoot,
  })  : _box = box,
        _notes = notesRepository,
        _documentsRootOverride = documentsRoot;

  static const String _boxName = 'received_inbox_v1';

  final NotesRepository _notes;
  final Directory? _documentsRootOverride;
  Box<dynamic>? _box;
  Directory? _documentsRoot;

  @override
  Future<void> init() async {
    final existing = _box;
    if (existing == null || !existing.isOpen) {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(_boxName);
    }
    _documentsRoot ??= _documentsRootOverride ?? await getApplicationDocumentsDirectory();
  }

  Box<dynamic> get _openBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('HiveReceivedInboxRepository.init() was not called.');
    }
    return box;
  }

  Directory get _docs {
    final root = _documentsRoot;
    if (root == null) {
      throw StateError('HiveReceivedInboxRepository.init() was not called.');
    }
    return root;
  }

  @override
  Future<List<ReceivedShare>> getAll() async {
    final entries =
        _openBox.values.cast<String>().map(ReceivedShare.fromJsonString).toList(growable: false);
    entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return entries;
  }

  @override
  Stream<List<ReceivedShare>> watchAll() async* {
    yield await getAll();
    await for (final _ in _openBox.watch()) {
      yield await getAll();
    }
  }

  @override
  Future<void> insert(ReceivedShare share) async {
    await _openBox.put(share.shareId, share.toJsonString());
  }

  @override
  Future<Note> accept(String shareId) async {
    final raw = _openBox.get(shareId);
    if (raw is! String) {
      throw StateError('No inbox entry for shareId=$shareId');
    }
    final share = ReceivedShare.fromJsonString(raw);

    final note = await _materializeNote(share);
    await _notes.save(note);

    // Save before cleanup: a partial cleanup leaves orphan files under
    // `<docs>/inbox/<shareId>/` that the next discard or app-clear
    // sweeps; the user-visible note is already in the library.
    await _openBox.delete(shareId);
    await _safelyDeleteDirectory(Directory(share.inboxRoot));

    return note;
  }

  @override
  Future<void> discard(String shareId) async {
    final raw = _openBox.get(shareId);
    await _openBox.delete(shareId);
    if (raw is String) {
      final share = ReceivedShare.fromJsonString(raw);
      await _safelyDeleteDirectory(Directory(share.inboxRoot));
    }
  }

  Future<Note> _materializeNote(ReceivedShare share) async {
    final assetsById = <String, IncomingAsset>{
      for (final a in share.assets) a.id: a,
    };
    final inboxRoot = Directory(share.inboxRoot);

    final imagesDir = Directory(p.join(_docs.path, 'notes', share.note.id, 'images'));
    final audioDir = Directory(p.join(_docs.path, 'notes', share.note.id, 'audio'));

    final rewrittenBlocks = <Map<String, dynamic>>[];
    for (final block in share.note.blocks) {
      final type = block['type'] as String?;
      final id = block['id'] as String?;
      if (id == null || (type != 'image' && type != 'audio')) {
        rewrittenBlocks.add(Map<String, dynamic>.from(block));
        continue;
      }
      final asset = assetsById[id];
      if (asset == null) {
        throw StateError('Block $id references missing asset in share ${share.shareId}');
      }
      // Defence in depth: `ShareDecoder` already runs `_isSafeAssetPath`
      // before signature verification, but the inbox box may have been
      // written by a different decoder build. Re-check the resolved path
      // sits inside `inboxRoot` so a crafted manifest cannot reach into
      // a sibling note's directory during the move.
      final resolved = p.normalize(p.join(inboxRoot.path, asset.pathInArchive));
      final inboxPrefix = '${inboxRoot.path}${p.separator}';
      if (!resolved.startsWith(inboxPrefix)) {
        throw StateError('Unsafe asset path in share ${share.shareId}: ${asset.pathInArchive}');
      }
      final source = File(resolved);
      final targetDir = asset.kind == ShareAssetKind.audio ? audioDir : imagesDir;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final ext = p.extension(asset.pathInArchive);
      final target = File(p.join(targetDir.path, '${asset.id}$ext'));
      await _moveFile(source, target);
      rewrittenBlocks.add(<String, dynamic>{
        ...block,
        'path': target.path,
      });
    }

    final overlay = share.note.overlay;
    final fontColor = overlay.onSurface ?? clampForReadability(overlay.surface);
    return Note(
      Set<String>.of(share.note.tags),
      null,
      overlay.patternKey?.name,
      const <Map<String, dynamic>>[],
      share.note.reminder,
      null,
      id: share.note.id,
      title: share.note.title,
      content: '',
      dateCreated: share.note.dateCreated,
      colorBackground: overlay.surface,
      fontColor: fontColor,
      hasGradient: false,
      isPinned: share.note.isPinned,
      blocks: rewrittenBlocks,
      fromIdentityId: share.sender.id,
      fromDisplayName: share.sender.displayName,
      fromAccentGlyph: share.sender.signatureAccent,
    );
  }

  /// `File.rename` is atomic on the same volume but throws on cross-mount
  /// moves (e.g. iOS app sandbox vs. shared container). Falling back to
  /// copy + delete keeps Accept working in those edge cases without
  /// leaving orphaned source bytes.
  Future<void> _moveFile(File source, File target) async {
    try {
      await source.rename(target.path);
      return;
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }

  Future<void> _safelyDeleteDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup: a missing or in-use directory must not roll
      // back the user's accept/discard. Orphans are swept on the next
      // accept or app-level clear.
    }
  }
}

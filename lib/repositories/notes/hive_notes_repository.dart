import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

/// Hive-backed implementation of [NotesRepository]. Continues to store each
/// note as a JSON-encoded string keyed by note id (legacy v2 format).
/// Migration to typed Hive CE adapters lands in Spec 04b.
class HiveNotesRepository implements NotesRepository {
  HiveNotesRepository({ImagePickerService? imageService})
      : _imageService = imageService ?? const ImagePickerService();

  @visibleForTesting
  HiveNotesRepository.withBox({
    required Box<dynamic> box,
    ImagePickerService? imageService,
  })  : _box = box,
        _imageService = imageService ?? const ImagePickerService();

  static const String _boxName = 'notes_v2';

  final ImagePickerService _imageService;
  Box<dynamic>? _box;

  @override
  Future<void> init() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Box<dynamic> get _openBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('HiveNotesRepository.init() was not called.');
    }
    return box;
  }

  @override
  Future<List<Note>> getAll() async {
    return _openBox.values
        .cast<String>()
        .map((s) => Note.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Stream<List<Note>> watchAll() async* {
    yield await getAll();
    await for (final _ in _openBox.watch()) {
      yield await getAll();
    }
  }

  @override
  Future<void> save(Note note) async {
    if (note.id.isEmpty) return;
    await _openBox.put(note.id, jsonEncode(note.toJson()));
  }

  @override
  Future<void> saveAll(Iterable<Note> notes) async {
    for (final n in notes) {
      await save(n);
    }
  }

  @override
  Future<void> delete(String id) async {
    final raw = _openBox.get(id);
    if (raw is String) {
      final note = Note.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final image = note.imageFile;
      if (image != null) {
        await _imageService.removeImage(image);
      }
    }
    await _openBox.delete(id);
  }

  @override
  Future<void> deleteAll(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<void> clear() async {
    final notes = await getAll();
    for (final n in notes) {
      final image = n.imageFile;
      if (image != null) {
        await _imageService.removeImage(image);
      }
    }
    await _openBox.clear();
  }
}

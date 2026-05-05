import 'dart:async';
import 'dart:convert';
import 'dart:io';

// `characters` is a transitive Flutter SDK dep; spec 09 forbids adding new
// pubspec entries, so we import it directly and silence the lint.
// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

/// Hive-backed implementation of [NotiIdentityRepository]. Stores the
/// single identity record as a JSON-encoded string keyed by
/// `'identityFromDevice'` in box `'noti_identity_v2'`. On first launch
/// after Spec 09 ships, [init] migrates the legacy `'user_v2'` box once,
/// then deletes it from disk.
class HiveNotiIdentityRepository implements NotiIdentityRepository {
  HiveNotiIdentityRepository({ImagePickerService? imageService})
      : _imageService = imageService ?? const ImagePickerService();

  @visibleForTesting
  HiveNotiIdentityRepository.withBox({
    required Box<dynamic> box,
    ImagePickerService? imageService,
  })  : _box = box,
        _imageService = imageService ?? const ImagePickerService();

  static const String _newBoxName = 'noti_identity_v2';
  static const String _legacyBoxName = 'user_v2';
  static const String _key = 'identityFromDevice';

  final ImagePickerService _imageService;
  Box<dynamic>? _box;
  final StreamController<NotiIdentity> _controller = StreamController<NotiIdentity>.broadcast();

  @override
  Future<void> init() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return;
    await Hive.initFlutter();
    final box = await Hive.openBox<dynamic>(_newBoxName);
    _box = box;
    if (box.isEmpty && await Hive.boxExists(_legacyBoxName)) {
      await _migrateFromLegacy();
    }
    if (box.isEmpty) {
      // Fresh install or legacy migration found nothing salvageable —
      // generate a new identity. Bypass save() to avoid emitting on a
      // stream nobody is listening to yet.
      final fresh = NotiIdentity.fresh();
      _validate(fresh);
      await box.put(_key, jsonEncode(fresh.toJson()));
    }
  }

  Box<dynamic> get _openBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('HiveNotiIdentityRepository.init() was not called.');
    }
    return box;
  }

  Future<void> _migrateFromLegacy() async {
    final legacy = await Hive.openBox<dynamic>(_legacyBoxName);
    final raw = legacy.get('userFromDevice') ?? (legacy.isNotEmpty ? legacy.values.first : null);
    if (raw is String) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final migrated = NotiIdentity(
        id: (json['id'] as String?) ?? '',
        displayName: (json['name'] as String?) ?? '',
        bornDate: DateTime.parse(
          (json['bornDate'] as String?) ?? DateTime.now().toIso8601String(),
        ),
        profilePicture:
            json['profilePicture'] != null ? File(json['profilePicture'] as String) : null,
        signaturePalette: List.of(NotiIdentityDefaults.starterPalettes.first),
      );
      _validate(migrated);
      await _openBox.put(_key, jsonEncode(migrated.toJson()));
    }
    await legacy.close();
    await Hive.deleteBoxFromDisk(_legacyBoxName);
  }

  @override
  Future<NotiIdentity> getCurrent() async {
    final raw = _openBox.get(_key);
    if (raw is String) {
      return NotiIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    final fresh = NotiIdentity.fresh();
    await save(fresh);
    return fresh;
  }

  @override
  Stream<NotiIdentity> watch() async* {
    yield await getCurrent();
    yield* _controller.stream;
  }

  @override
  Future<void> save(NotiIdentity identity) async {
    _validate(identity);
    await _openBox.put(_key, jsonEncode(identity.toJson()));
    _controller.add(identity);
  }

  @override
  Future<void> setPhoto(NotiIdentity identity, File? newPhoto) async {
    final old = identity.profilePicture;
    if (old != null && old.path != newPhoto?.path) {
      await _imageService.removeImage(old);
    }
    identity.profilePicture = newPhoto;
    await save(identity);
  }

  @override
  Future<void> removePhoto(NotiIdentity identity) async {
    final old = identity.profilePicture;
    if (old == null) return;
    await _imageService.removeImage(old);
    identity.profilePicture = null;
    await save(identity);
  }

  void _validate(NotiIdentity i) {
    final accent = i.signatureAccent;
    if (accent != null && accent.isNotEmpty) {
      final length = accent.characters.length;
      if (length != 1) {
        throw ArgumentError(
          'signatureAccent must be exactly one grapheme; got "$accent" ($length)',
        );
      }
    }
    if (i.signatureTagline.length > 60) {
      throw ArgumentError(
        'signatureTagline must be ≤ 60 chars; got ${i.signatureTagline.length}',
      );
    }
    if (i.signaturePalette.isEmpty) {
      throw ArgumentError('signaturePalette must contain at least one swatch');
    }
  }
}

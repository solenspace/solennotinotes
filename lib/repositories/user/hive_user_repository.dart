import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/user.dart';
import 'package:noti_notes_app/repositories/user/user_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

/// Hive-backed implementation of [UserRepository]. Stores the single user
/// record as a JSON-encoded string keyed by `'userFromDevice'` in box
/// `'user_v2'` (legacy compatibility). Migration to typed Hive CE adapters
/// is reserved for a future user-adapter spec.
class HiveUserRepository implements UserRepository {
  HiveUserRepository({ImagePickerService? imageService})
      : _imageService = imageService ?? const ImagePickerService();

  @visibleForTesting
  HiveUserRepository.withBox({
    required Box<dynamic> box,
    ImagePickerService? imageService,
  })  : _box = box,
        _imageService = imageService ?? const ImagePickerService();

  static const String _boxName = 'user_v2';
  static const String _key = 'userFromDevice';

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
      throw StateError('HiveUserRepository.init() was not called.');
    }
    return box;
  }

  @override
  Future<User?> getCurrent() async {
    final raw = _openBox.get(_key);
    if (raw is! String) return null;
    return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Stream<User?> watch() async* {
    yield await getCurrent();
    await for (final _ in _openBox.watch(key: _key)) {
      yield await getCurrent();
    }
  }

  @override
  Future<void> save(User user) async {
    await _openBox.put(_key, jsonEncode(user.toJson()));
  }

  @override
  Future<void> setPhoto(User user, File? newPhoto) async {
    final old = user.profilePicture;
    if (old != null && old.path != newPhoto?.path) {
      await _imageService.removeImage(old);
    }
    user.profilePicture = newPhoto;
    await save(user);
  }

  @override
  Future<void> removePhoto(User user) async {
    final old = user.profilePicture;
    if (old == null) return;
    await _imageService.removeImage(old);
    user.profilePicture = null;
    await save(user);
  }
}

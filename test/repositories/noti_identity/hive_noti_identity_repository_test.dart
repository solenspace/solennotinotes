import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/noti_identity/hive_noti_identity_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

import '../../services/crypto/fake_keypair_service.dart';

class _RecordingImageService implements ImagePickerService {
  final List<File> removed = [];

  @override
  Future<File?> pickImage(ImageSource source, int quality) async => null;

  @override
  Future<void> removeImage(File image) async {
    removed.add(image);
  }
}

NotiIdentity _buildIdentity({
  String id = 'identity-1',
  String displayName = 'Mateo',
  DateTime? bornDate,
  File? profilePicture,
  List<Color>? signaturePalette,
  String? signaturePatternKey,
  String? signatureAccent,
  String signatureTagline = '',
}) {
  return NotiIdentity(
    id: id,
    displayName: displayName,
    bornDate: bornDate ?? DateTime(2026, 5, 4),
    profilePicture: profilePicture,
    signaturePalette: signaturePalette ?? List.of(NotiIdentityDefaults.starterPalettes.first),
    signaturePatternKey: signaturePatternKey,
    signatureAccent: signatureAccent,
    signatureTagline: signatureTagline,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HiveNotiIdentityRepository (withBox unit tests)', () {
    late Directory tempDir;
    late Box<dynamic> box;
    late _RecordingImageService imageService;
    late HiveNotiIdentityRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_noti_id_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox<dynamic>('noti_identity_v2');
      imageService = _RecordingImageService();
      repo = HiveNotiIdentityRepository.withBox(
        box: box,
        imageService: imageService,
        keypairService: FakeKeypairService(),
      );
    });

    tearDown(() async {
      await box.close();
      await Hive.deleteBoxFromDisk('noti_identity_v2');
      await tempDir.delete(recursive: true);
    });

    test('init is idempotent when the box is already open', () async {
      await repo.init();
      await repo.init();
      expect(box.isOpen, isTrue);
    });

    test('save then getCurrent round-trips an identity record', () async {
      final identity = _buildIdentity(displayName: 'Mateo');
      await repo.save(identity);

      final fetched = await repo.getCurrent();
      expect(fetched.id, identity.id);
      expect(fetched.displayName, 'Mateo');
      expect(fetched.bornDate, identity.bornDate);
      expect(fetched.profilePicture, isNull);
      expect(
        fetched.signaturePalette.first.toARGB32(),
        identity.signaturePalette.first.toARGB32(),
      );
    });

    test('round-trip preserves all signature fields', () async {
      await repo.save(
        _buildIdentity(
          signaturePalette: const [Color(0xFF112233), Color(0xFF445566)],
          signaturePatternKey: 'waves',
          signatureAccent: '🌊',
          signatureTagline: 'Hello, world.',
        ),
      );

      final fetched = await repo.getCurrent();
      expect(fetched.signaturePalette, hasLength(2));
      expect(fetched.signaturePalette[0].toARGB32(), 0xFF112233);
      expect(fetched.signaturePalette[1].toARGB32(), 0xFF445566);
      expect(fetched.signaturePatternKey, 'waves');
      expect(fetched.signatureAccent, '🌊');
      expect(fetched.signatureTagline, 'Hello, world.');
    });

    test('round-trip preserves a profile picture path', () async {
      final picture = File('${tempDir.path}/avatar.png');
      await picture.writeAsBytes([1, 2, 3]);
      await repo.save(_buildIdentity(profilePicture: picture));

      final fetched = await repo.getCurrent();
      expect(fetched.profilePicture, isNotNull);
      expect(fetched.profilePicture!.path, picture.path);
    });

    test('watch emits the initial snapshot then re-emits on save', () async {
      await repo.save(_buildIdentity(displayName: 'before'));

      final future = expectLater(
        repo.watch().take(2),
        emitsInOrder([
          predicate<NotiIdentity>(
            (i) => i.displayName == 'before',
            'snapshot with "before"',
          ),
          predicate<NotiIdentity>(
            (i) => i.displayName == 'after',
            'snapshot with "after"',
          ),
        ]),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.save(_buildIdentity(displayName: 'after'));

      await future;
    });

    test('setPhoto removes the previous file when the path changes', () async {
      final oldPicture = File('${tempDir.path}/old.png');
      final newPicture = File('${tempDir.path}/new.png');
      await oldPicture.writeAsBytes([1]);
      await newPicture.writeAsBytes([2]);

      final identity = _buildIdentity(profilePicture: oldPicture);
      await repo.save(identity);

      await repo.setPhoto(identity, newPicture);
      expect(imageService.removed, hasLength(1));
      expect(imageService.removed.single.path, oldPicture.path);
      expect(identity.profilePicture!.path, newPicture.path);

      final fetched = await repo.getCurrent();
      expect(fetched.profilePicture!.path, newPicture.path);
    });

    test('setPhoto skips removal when the new path matches the old', () async {
      final picture = File('${tempDir.path}/same.png');
      await picture.writeAsBytes([1]);
      final identity = _buildIdentity(profilePicture: picture);
      await repo.save(identity);

      await repo.setPhoto(identity, picture);
      expect(imageService.removed, isEmpty);
    });

    test('setPhoto with null clears the field and removes the previous file', () async {
      final picture = File('${tempDir.path}/byebye.png');
      await picture.writeAsBytes([1]);
      final identity = _buildIdentity(profilePicture: picture);
      await repo.save(identity);

      await repo.setPhoto(identity, null);
      expect(imageService.removed.single.path, picture.path);
      expect(identity.profilePicture, isNull);
      expect((await repo.getCurrent()).profilePicture, isNull);
    });

    test('removePhoto cleans up the file and clears the field', () async {
      final picture = File('${tempDir.path}/bye.png');
      await picture.writeAsBytes([1]);
      final identity = _buildIdentity(profilePicture: picture);
      await repo.save(identity);

      await repo.removePhoto(identity);
      expect(imageService.removed.single.path, picture.path);
      expect(identity.profilePicture, isNull);
      expect((await repo.getCurrent()).profilePicture, isNull);
    });

    test('removePhoto is a no-op when the picture is already null', () async {
      final identity = _buildIdentity();
      await repo.save(identity);

      await repo.removePhoto(identity);
      expect(imageService.removed, isEmpty);
    });

    test('save rejects multi-grapheme signatureAccent', () async {
      expect(
        () => repo.save(_buildIdentity(signatureAccent: 'ab')),
        throwsArgumentError,
      );
    });

    test('save accepts a single-grapheme emoji even when multi-codepoint', () async {
      // Family emoji is a single user-perceived character but multiple
      // code points; grapheme counting (via `characters`) handles it.
      await repo.save(_buildIdentity(signatureAccent: '👨‍👩‍👧'));
      expect((await repo.getCurrent()).signatureAccent, '👨‍👩‍👧');
    });

    test('save rejects signatureTagline > 60 chars', () async {
      expect(
        () => repo.save(_buildIdentity(signatureTagline: 'x' * 61)),
        throwsArgumentError,
      );
    });

    test('save rejects empty signaturePalette', () async {
      expect(
        () => repo.save(_buildIdentity(signaturePalette: const [])),
        throwsArgumentError,
      );
    });
  });

  group('HiveNotiIdentityRepository.init() — first-launch + migration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_noti_id_init_test_');
      // Mock path_provider so Hive.initFlutter() lands inside our temp dir.
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
    });

    tearDown(() async {
      await Hive.close();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tempDir.delete(recursive: true);
    });

    test('fresh install generates a new identity with a starter palette', () async {
      final repo = HiveNotiIdentityRepository(keypairService: FakeKeypairService());
      await repo.init();

      final fetched = await repo.getCurrent();
      expect(fetched.id, isNotEmpty);
      expect(fetched.displayName, isEmpty);
      expect(fetched.signaturePalette, isNotEmpty);

      final fetchedArgb = fetched.signaturePalette.map((c) => c.toARGB32()).toList(growable: false);
      final matchesAStarter = NotiIdentityDefaults.starterPalettes.any((palette) {
        if (palette.length != fetchedArgb.length) return false;
        for (var i = 0; i < palette.length; i++) {
          if (palette[i].toARGB32() != fetchedArgb[i]) return false;
        }
        return true;
      });
      expect(
        matchesAStarter,
        isTrue,
        reason: 'fresh-install palette $fetchedArgb did not match any '
            'starter palette',
      );
    });

    test('migrates a legacy user_v2 record and deletes the old box', () async {
      // Seed legacy box.
      Hive.init(tempDir.path);
      final legacy = await Hive.openBox<dynamic>('user_v2');
      await legacy.put(
        'userFromDevice',
        jsonEncode({
          'id': 'legacy-uuid',
          'name': 'Legacy User',
          'bornDate': DateTime(2020, 1, 1).toIso8601String(),
          'profilePicture': null,
        }),
      );
      await legacy.close();
      await Hive.close();

      final repo = HiveNotiIdentityRepository(keypairService: FakeKeypairService());
      await repo.init();

      final fetched = await repo.getCurrent();
      expect(fetched.id, 'legacy-uuid');
      expect(fetched.displayName, 'Legacy User');
      expect(fetched.bornDate, DateTime(2020, 1, 1));
      expect(fetched.profilePicture, isNull);
      expect(
        fetched.signaturePalette.map((c) => c.toARGB32()),
        NotiIdentityDefaults.starterPalettes.first.map((c) => c.toARGB32()),
      );

      expect(await Hive.boxExists('user_v2'), isFalse);
    });

    test('init is idempotent when called twice (no double-migration)', () async {
      final repo = HiveNotiIdentityRepository(keypairService: FakeKeypairService());
      await repo.init();
      final firstId = (await repo.getCurrent()).id;

      await repo.init();
      final secondId = (await repo.getCurrent()).id;

      expect(secondId, firstId);
    });
  });
}

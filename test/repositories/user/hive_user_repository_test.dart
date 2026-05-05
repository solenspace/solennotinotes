import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noti_notes_app/models/user.dart';
import 'package:noti_notes_app/repositories/user/hive_user_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

class _RecordingImageService implements ImagePickerService {
  final List<File> removed = [];

  @override
  Future<File?> pickImage(ImageSource source, int quality) async => null;

  @override
  Future<void> removeImage(File image) async {
    removed.add(image);
  }
}

User _buildUser({
  String id = 'user-1',
  String name = 'Mateo',
  DateTime? bornDate,
  File? profilePicture,
}) {
  return User(
    profilePicture,
    id,
    name: name,
    bornDate: bornDate ?? DateTime(2026, 5, 4),
  );
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late _RecordingImageService imageService;
  late HiveUserRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_user_repo_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('user_v2');
    imageService = _RecordingImageService();
    repo = HiveUserRepository.withBox(box: box, imageService: imageService);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('user_v2');
    await tempDir.delete(recursive: true);
  });

  group('HiveUserRepository', () {
    test('init is idempotent when the box is already open', () async {
      await repo.init();
      await repo.init();
      expect(box.isOpen, isTrue);
    });

    test('getCurrent returns null when the box is empty', () async {
      expect(await repo.getCurrent(), isNull);
    });

    test('save then getCurrent round-trips a user record', () async {
      final user = _buildUser(name: 'Mateo');
      await repo.save(user);

      final fetched = await repo.getCurrent();
      expect(fetched, isNotNull);
      expect(fetched!.id, user.id);
      expect(fetched.name, 'Mateo');
      expect(fetched.bornDate, user.bornDate);
      expect(fetched.profilePicture, isNull);
    });

    test('round-trip preserves a profile picture path', () async {
      final picture = File('${tempDir.path}/avatar.png');
      await picture.writeAsBytes([1, 2, 3]);
      await repo.save(_buildUser(profilePicture: picture));

      final fetched = await repo.getCurrent();
      expect(fetched!.profilePicture, isNotNull);
      expect(fetched.profilePicture!.path, picture.path);
    });

    test('watch emits the initial snapshot then re-emits on save', () async {
      await repo.save(_buildUser(name: 'before'));

      final future = expectLater(
        repo.watch().take(2),
        emitsInOrder([
          predicate<User?>((u) => u?.name == 'before', 'snapshot with "before"'),
          predicate<User?>((u) => u?.name == 'after', 'snapshot with "after"'),
        ]),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.save(_buildUser(name: 'after'));

      await future;
    });

    test('setPhoto removes the previous file when the path changes', () async {
      final oldPicture = File('${tempDir.path}/old.png');
      final newPicture = File('${tempDir.path}/new.png');
      await oldPicture.writeAsBytes([1]);
      await newPicture.writeAsBytes([2]);

      final user = _buildUser(profilePicture: oldPicture);
      await repo.save(user);

      await repo.setPhoto(user, newPicture);
      expect(imageService.removed, hasLength(1));
      expect(imageService.removed.single.path, oldPicture.path);
      expect(user.profilePicture!.path, newPicture.path);

      final fetched = await repo.getCurrent();
      expect(fetched!.profilePicture!.path, newPicture.path);
    });

    test('setPhoto skips removal when the new path matches the old', () async {
      final picture = File('${tempDir.path}/same.png');
      await picture.writeAsBytes([1]);
      final user = _buildUser(profilePicture: picture);
      await repo.save(user);

      await repo.setPhoto(user, picture);
      expect(imageService.removed, isEmpty);
    });

    test('setPhoto with null clears the field and removes the previous file', () async {
      final picture = File('${tempDir.path}/byebye.png');
      await picture.writeAsBytes([1]);
      final user = _buildUser(profilePicture: picture);
      await repo.save(user);

      await repo.setPhoto(user, null);
      expect(imageService.removed.single.path, picture.path);
      expect(user.profilePicture, isNull);
      expect((await repo.getCurrent())!.profilePicture, isNull);
    });

    test('removePhoto cleans up the file and clears the field', () async {
      final picture = File('${tempDir.path}/bye.png');
      await picture.writeAsBytes([1]);
      final user = _buildUser(profilePicture: picture);
      await repo.save(user);

      await repo.removePhoto(user);
      expect(imageService.removed.single.path, picture.path);
      expect(user.profilePicture, isNull);
      expect((await repo.getCurrent())!.profilePicture, isNull);
    });

    test('removePhoto is a no-op when the picture is already null', () async {
      final user = _buildUser();
      await repo.save(user);

      await repo.removePhoto(user);
      expect(imageService.removed, isEmpty);
    });
  });
}

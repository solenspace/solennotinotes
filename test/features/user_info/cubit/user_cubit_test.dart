import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/user_info/cubit/user_cubit.dart';
import 'package:noti_notes_app/features/user_info/cubit/user_state.dart';
import 'package:noti_notes_app/models/user.dart';

import '../../../repositories/user/fake_user_repository.dart';

User _buildUser({
  String id = 'u1',
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

Future<List<UserState>> _drain(
  UserCubit cubit,
  Future<void> Function() act, {
  int expectedCount = 1,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final emissions = <UserState>[];
  final sub = cubit.stream.listen(emissions.add);
  await act();
  final deadline = DateTime.now().add(timeout);
  while (emissions.length < expectedCount && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await sub.cancel();
  return emissions;
}

void main() {
  late FakeUserRepository fake;

  UserCubit buildCubit({Random? random}) =>
      UserCubit(repository: fake, random: random ?? Random(0));

  setUp(() {
    fake = FakeUserRepository();
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('UserCubit', () {
    test('initial state is initial status with greeting "Noti"', () {
      final cubit = buildCubit();
      expect(cubit.state.status, UserStatus.initial);
      expect(cubit.state.user, isNull);
      expect(cubit.state.greeting, 'Noti');
      cubit.close();
    });

    test('load emits loading then ready with the persisted user', () async {
      final saved = _buildUser(name: 'Mateo');
      fake.emit(saved);

      final cubit = buildCubit();
      final emissions = await _drain(cubit, () => cubit.load(), expectedCount: 2);

      expect(emissions[0].status, UserStatus.loading);
      expect(emissions[1].status, UserStatus.ready);
      expect(emissions[1].user!.id, saved.id);
      expect(emissions[1].user!.name, 'Mateo');
      expect(emissions[1].greeting, isNotEmpty);
      expect(emissions[1].greeting, isNot('Noti'));
      await cubit.close();
    });

    test('load synthesizes a fresh empty user when the repo is empty', () async {
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      expect(cubit.state.status, UserStatus.ready);
      expect(cubit.state.user, isNotNull);
      expect(cubit.state.user!.name, isEmpty);
      await cubit.close();
    });

    test('updateName persists the new name and emits a fresh user instance', () async {
      fake.emit(_buildUser(name: 'before'));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);
      final beforeUser = cubit.state.user;

      await cubit.updateName('after');

      expect(fake.savedUsers, isNotEmpty);
      expect(fake.savedUsers.last.name, 'after');
      expect(cubit.state.user!.name, 'after');
      // Cloned, not the same reference — so BlocBuilder rebuilds reliably.
      expect(identical(cubit.state.user, beforeUser), isFalse);
      await cubit.close();
    });

    test('updateName is a no-op when no user is loaded', () async {
      final cubit = buildCubit();
      await cubit.updateName('whatever');
      expect(fake.savedUsers, isEmpty);
      await cubit.close();
    });

    test('updatePhoto delegates to repository.setPhoto', () async {
      fake.emit(_buildUser());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      final picture = File('/tmp/test_avatar.png');
      await cubit.updatePhoto(picture);

      expect(fake.setPhotoCalls, hasLength(1));
      expect(fake.setPhotoCalls.single.newPhoto?.path, picture.path);
      expect(cubit.state.user!.profilePicture?.path, picture.path);
      await cubit.close();
    });

    test('removePhoto delegates to repository.removePhoto when a photo exists', () async {
      final picture = File('/tmp/old_avatar.png');
      fake.emit(_buildUser(profilePicture: picture));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.removePhoto();

      expect(fake.removedPhotos, hasLength(1));
      expect(fake.removedPhotos.single.path, picture.path);
      expect(cubit.state.user!.profilePicture, isNull);
      await cubit.close();
    });

    test('removePhoto is a no-op when no photo is set', () async {
      fake.emit(_buildUser());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.removePhoto();
      expect(fake.removedPhotos, isEmpty);
      await cubit.close();
    });
  });
}

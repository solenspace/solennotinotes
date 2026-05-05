import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_state.dart';
import 'package:noti_notes_app/models/noti_identity.dart';

import '../../../repositories/noti_identity/fake_noti_identity_repository.dart';

/// Always returns `index` (clamped to `max - 1`). Lets us pin to a
/// specific entry in the greeting pool without relying on Dart's
/// PRNG implementation details.
class _FixedRandom implements Random {
  _FixedRandom(this.index);
  final int index;

  @override
  int nextInt(int max) => index < max ? index : max - 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

NotiIdentity _buildIdentity({
  String id = 'i1',
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

Future<List<NotiIdentityState>> _drain(
  NotiIdentityCubit cubit,
  Future<void> Function() act, {
  int expectedCount = 1,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final emissions = <NotiIdentityState>[];
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
  late FakeNotiIdentityRepository fake;

  NotiIdentityCubit buildCubit() => NotiIdentityCubit(repository: fake);

  setUp(() {
    fake = FakeNotiIdentityRepository();
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('NotiIdentityCubit', () {
    test('initial state is initial status with no identity', () {
      final cubit = buildCubit();
      expect(cubit.state.status, NotiIdentityStatus.initial);
      expect(cubit.state.identity, isNull);
      cubit.close();
    });

    test('load emits loading then ready with the persisted identity', () async {
      final saved = _buildIdentity(displayName: 'Mateo');
      fake.emit(saved);

      final cubit = buildCubit();
      final emissions = await _drain(cubit, () => cubit.load(), expectedCount: 2);

      expect(emissions[0].status, NotiIdentityStatus.loading);
      expect(emissions[1].status, NotiIdentityStatus.ready);
      expect(emissions[1].identity!.id, saved.id);
      expect(emissions[1].identity!.displayName, 'Mateo');
      await cubit.close();
    });

    test('load synthesizes a fresh identity when the repo is empty', () async {
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      expect(cubit.state.status, NotiIdentityStatus.ready);
      expect(cubit.state.identity, isNotNull);
      expect(cubit.state.identity!.signaturePalette, isNotEmpty);
      await cubit.close();
    });

    test('updateDisplayName saves and emits a fresh instance', () async {
      fake.emit(_buildIdentity(displayName: 'before'));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);
      final beforeIdentity = cubit.state.identity;

      await cubit.updateDisplayName('after');

      expect(fake.savedIdentities, isNotEmpty);
      expect(fake.savedIdentities.last.displayName, 'after');
      expect(cubit.state.identity!.displayName, 'after');
      // Cloned via copyWith, not the same reference — so BlocBuilder
      // rebuilds reliably under Equatable's emit dedup.
      expect(identical(cubit.state.identity, beforeIdentity), isFalse);
      await cubit.close();
    });

    test('updateDisplayName is a no-op when no identity is loaded', () async {
      final cubit = buildCubit();
      await cubit.updateDisplayName('whatever');
      expect(fake.savedIdentities, isEmpty);
      await cubit.close();
    });

    test('updatePhoto delegates to repository.setPhoto', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      final picture = File('/tmp/test_avatar.png');
      await cubit.updatePhoto(picture);

      expect(fake.setPhotoCalls, hasLength(1));
      expect(fake.setPhotoCalls.single.newPhoto?.path, picture.path);
      expect(cubit.state.identity!.profilePicture?.path, picture.path);
      await cubit.close();
    });

    test('removePhoto delegates to repository.removePhoto when a photo exists', () async {
      final picture = File('/tmp/old_avatar.png');
      fake.emit(_buildIdentity(profilePicture: picture));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.removePhoto();

      expect(fake.removedPhotos, hasLength(1));
      expect(fake.removedPhotos.single.path, picture.path);
      expect(cubit.state.identity!.profilePicture, isNull);
      await cubit.close();
    });

    test('removePhoto is a no-op when no photo is set', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.removePhoto();
      expect(fake.removedPhotos, isEmpty);
      await cubit.close();
    });

    test('updatePalette saves the new swatches', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      const swatches = [Color(0xFFAABBCC), Color(0xFFDDEEFF)];
      await cubit.updatePalette(swatches);

      expect(fake.savedIdentities.last.signaturePalette.length, 2);
      expect(
        fake.savedIdentities.last.signaturePalette.first.toARGB32(),
        0xFFAABBCC,
      );
      expect(
        cubit.state.identity!.signaturePalette.last.toARGB32(),
        0xFFDDEEFF,
      );
      await cubit.close();
    });

    test('updatePatternKey persists the new key and clears with null', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.updatePatternKey('waves');
      expect(cubit.state.identity!.signaturePatternKey, 'waves');

      await cubit.updatePatternKey(null);
      expect(cubit.state.identity!.signaturePatternKey, isNull);
      await cubit.close();
    });

    test('updateAccent normalizes empty string to null', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.updateAccent('🎉');
      expect(cubit.state.identity!.signatureAccent, '🎉');

      await cubit.updateAccent('');
      expect(cubit.state.identity!.signatureAccent, isNull);
      await cubit.close();
    });

    test('updateTagline persists the new tagline', () async {
      fake.emit(_buildIdentity());
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      await cubit.updateTagline('Hello');
      expect(cubit.state.identity!.signatureTagline, 'Hello');
      await cubit.close();
    });

    test('greetingFor returns a non-empty string once loaded', () async {
      fake.emit(_buildIdentity(displayName: 'Alice'));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      final greeting = cubit.state.greetingFor(DateTime(2026, 5, 6));
      expect(greeting, isNotEmpty);
      await cubit.close();
    });

    test('greetingFor reflects the latest displayName after rename', () async {
      // Wednesday so we hit the default pool, where index 2 is the
      // "$name, glad you're back." entry — confirms name interpolation.
      final wednesday = DateTime(2026, 5, 6, 10);
      final fixed = _FixedRandom(2);

      fake.emit(_buildIdentity(displayName: 'Alice'));
      final cubit = buildCubit();
      await _drain(cubit, () => cubit.load(), expectedCount: 2);

      final firstGreeting = cubit.state.greetingFor(wednesday, random: fixed);
      expect(firstGreeting.toLowerCase(), contains('alice'));

      await cubit.updateDisplayName('Bob');
      final secondGreeting = cubit.state.greetingFor(wednesday, random: fixed);
      expect(secondGreeting.toLowerCase(), contains('bob'));
      expect(secondGreeting.toLowerCase(), isNot(contains('alice')));

      await cubit.close();
    });
  });
}

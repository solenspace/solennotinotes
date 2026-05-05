import 'dart:io';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:intl/intl.dart';
import 'package:noti_notes_app/models/user.dart';
import 'package:noti_notes_app/repositories/user/user_repository.dart';
import 'package:uuid/uuid.dart';

import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  UserCubit({required UserRepository repository, Random? random})
      : _repository = repository,
        _random = random ?? Random(),
        super(const UserState());

  final UserRepository _repository;
  final Random _random;

  Future<void> load() async {
    emit(state.copyWith(status: UserStatus.loading, clearError: true));
    final loaded = await _repository.getCurrent() ?? _emptyUser();
    emit(
      state.copyWith(
        status: UserStatus.ready,
        user: loaded,
        greeting: _pickGreeting(loaded),
        clearError: true,
      ),
    );
  }

  Future<void> updateName(String name) async {
    final user = state.user;
    if (user == null) return;
    final updated = _clone(user, name: name);
    await _repository.save(updated);
    emit(state.copyWith(user: updated));
  }

  Future<void> updatePhoto(File photo) async {
    final user = state.user;
    if (user == null) return;
    await _repository.setPhoto(user, photo);
    emit(state.copyWith(user: _clone(user)));
  }

  Future<void> removePhoto() async {
    final user = state.user;
    if (user == null || user.profilePicture == null) return;
    await _repository.removePhoto(user);
    emit(state.copyWith(user: _clone(user)));
  }

  User _emptyUser() => User(
        null,
        const Uuid().v4(),
        name: '',
        bornDate: DateTime.now(),
      );

  User _clone(User source, {String? name}) => User(
        source.profilePicture,
        source.id,
        name: name ?? source.name,
        bornDate: source.bornDate,
      );

  String _pickGreeting(User user) {
    final hour = DateTime.now().hour;
    final timeOfDay = hour < 12 ? 'Morning' : (hour < 17 ? 'Afternoon' : 'Evening');
    final day = DateFormat('EEEE').format(DateTime.now());
    final name = user.name.isEmpty ? 'User' : user.name.toLowerCase();

    final pool = switch (day) {
      'Monday' => [
          'Another monday, ugh...',
          'Starting the week.',
          "Let's get things done.",
          "$name, you'll crush it.",
        ],
      'Tuesday' => [
          'Tuesday, not monday.',
          'Taco tuesday?',
          'today is... not monday!',
          '$name, feeling good?',
        ],
      _ => [
          'Good $timeOfDay',
          'Today is the day.',
          "$name, glad you're back.",
          "You're doing great.",
          'Good $timeOfDay $name',
          'Plans for the weekend?',
          '$name, did you shower?',
          "Tonight's the night.",
          'This is your notinotes.',
        ],
    };

    return pool[_random.nextInt(pool.length)];
  }
}

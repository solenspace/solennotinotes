import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';
import 'package:noti_notes_app/models/noti_identity.dart';

enum NotiIdentityStatus { initial, loading, ready, error }

class NotiIdentityState extends Equatable {
  const NotiIdentityState({
    this.status = NotiIdentityStatus.initial,
    this.identity,
    this.errorMessage,
  });

  final NotiIdentityStatus status;
  final NotiIdentity? identity;
  final String? errorMessage;

  /// Time-of-day greeting derived from the current identity. Recomputed
  /// each time it's read so a name change reflects immediately.
  String greetingFor(DateTime now, {Random? random}) {
    final id = identity;
    if (id == null) return 'Noti';
    final rng = random ?? Random();
    final timeOfDay = now.hour < 12 ? 'Morning' : (now.hour < 17 ? 'Afternoon' : 'Evening');
    final day = DateFormat('EEEE').format(now);
    final name = id.displayName.isEmpty ? 'User' : id.displayName.toLowerCase();

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

    return pool[rng.nextInt(pool.length)];
  }

  NotiIdentityState copyWith({
    NotiIdentityStatus? status,
    NotiIdentity? identity,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotiIdentityState(
      status: status ?? this.status,
      identity: identity ?? this.identity,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, identity, errorMessage];
}

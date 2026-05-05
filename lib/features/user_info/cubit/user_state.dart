import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/user.dart';

enum UserStatus { initial, loading, ready, error }

class UserState extends Equatable {
  const UserState({
    this.status = UserStatus.initial,
    this.user,
    this.greeting = 'Noti',
    this.errorMessage,
  });

  final UserStatus status;
  final User? user;
  final String greeting;
  final String? errorMessage;

  UserState copyWith({
    UserStatus? status,
    User? user,
    String? greeting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UserState(
      status: status ?? this.status,
      user: user ?? this.user,
      greeting: greeting ?? this.greeting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, user, greeting, errorMessage];
}

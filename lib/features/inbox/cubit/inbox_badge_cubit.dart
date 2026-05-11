import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';

/// Tiny app-shell cubit that streams the count of pending inbox
/// entries for the home AppBar badge. Emits 0 when the inbox is
/// empty so the badge widget can elide itself.
class InboxBadgeCubit extends Cubit<int> {
  InboxBadgeCubit({required ReceivedInboxRepository repository})
      : _repository = repository,
        super(0);

  final ReceivedInboxRepository _repository;
  StreamSubscription<List<ReceivedShare>>? _sub;

  void start() {
    _sub ??= _repository.watchAll().listen((entries) {
      if (isClosed) return;
      emit(entries.length);
    });
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_listener_service.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_state.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';

/// Owns the inbox screen's state: subscribes the repository's
/// `watchAll` for entry-list updates and the listener service's
/// `events` stream so transient decode failures can surface as
/// SnackBars without colluding with persisted state.
class InboxCubit extends Cubit<InboxState> {
  InboxCubit({
    required ReceivedInboxRepository repository,
    required InboxListenerService listener,
  })  : _repository = repository,
        _listener = listener,
        super(
          InboxState(
            listener: listener.isReceiving ? InboxListenerStatus.on : InboxListenerStatus.off,
          ),
        );

  final ReceivedInboxRepository _repository;
  final InboxListenerService _listener;

  StreamSubscription<List<ReceivedShare>>? _entriesSub;
  StreamSubscription<InboxListenerEvent>? _eventsSub;

  final StreamController<InboxListenerEvent> _uiEvents =
      StreamController<InboxListenerEvent>.broadcast();

  /// One-shot side-channel for the screen to render SnackBars on
  /// `decodeRejected` / `peerStartFailed`. Decoupled from `state` so a
  /// rebuild doesn't replay the same toast.
  Stream<InboxListenerEvent> get uiEvents => _uiEvents.stream;

  void start() {
    _entriesSub ??= _repository.watchAll().listen((entries) {
      if (isClosed) return;
      emit(state.copyWith(entries: entries));
    });
    _eventsSub ??= _listener.events.listen((event) {
      if (isClosed) return;
      _uiEvents.add(event);
    });
  }

  Future<void> startReceiving() async {
    if (state.listener == InboxListenerStatus.on ||
        state.listener == InboxListenerStatus.starting) {
      return;
    }
    emit(state.copyWith(listener: InboxListenerStatus.starting, clearFailureDetail: true));
    try {
      await _listener.startReceiving();
      if (isClosed) return;
      emit(state.copyWith(listener: InboxListenerStatus.on));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(listener: InboxListenerStatus.failed, failureDetail: '$e'));
    }
  }

  Future<void> stopReceiving() async {
    await _listener.stopReceiving();
    if (isClosed) return;
    emit(state.copyWith(listener: InboxListenerStatus.off, clearFailureDetail: true));
  }

  Future<Note> accept(String shareId) => _repository.accept(shareId);

  Future<void> discard(String shareId) => _repository.discard(shareId);

  @override
  Future<void> close() async {
    await _entriesSub?.cancel();
    await _eventsSub?.cancel();
    await _uiEvents.close();
    await _listener.dispose();
    return super.close();
  }
}

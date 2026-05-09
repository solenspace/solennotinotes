import 'package:equatable/equatable.dart';

sealed class NotesListEvent extends Equatable {
  const NotesListEvent();

  @override
  List<Object?> get props => const [];
}

final class NotesListSubscribed extends NotesListEvent {
  const NotesListSubscribed();
}

final class PinToggled extends NotesListEvent {
  const PinToggled(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class NoteDeleted extends NotesListEvent {
  const NoteDeleted(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class NoteBlocksReplaced extends NotesListEvent {
  const NoteBlocksReplaced(this.id, this.blocks);
  final String id;
  final List<Map<String, dynamic>> blocks;
  @override
  List<Object?> get props => [id, blocks];
}

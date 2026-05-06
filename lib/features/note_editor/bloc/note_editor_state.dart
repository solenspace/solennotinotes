import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/note.dart';

enum NoteEditorStatus { initial, loading, ready, notFound, saving, error }

class NoteEditorState extends Equatable {
  const NoteEditorState({
    this.status = NoteEditorStatus.initial,
    this.note,
    this.popRequested = false,
    this.errorMessage,
    this.accentOverride,
  });

  final NoteEditorStatus status;
  final Note? note;

  /// One-shot signal: when true, the screen should pop the route. The next
  /// state emission will reset this to false.
  final bool popRequested;

  final String? errorMessage;

  /// In-memory carry of the per-note signature accent glyph. The legacy
  /// [Note] schema has no place to store it; Spec 04b promotes
  /// `Note.overlay: NotiThemeOverlay` and this field retires.
  final String? accentOverride;

  NoteEditorState copyWith({
    NoteEditorStatus? status,
    Note? note,
    bool? popRequested,
    String? errorMessage,
    bool clearError = false,
    String? accentOverride,
    bool clearAccentOverride = false,
  }) {
    return NoteEditorState(
      status: status ?? this.status,
      note: note ?? this.note,
      popRequested: popRequested ?? false,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      accentOverride: clearAccentOverride ? null : (accentOverride ?? this.accentOverride),
    );
  }

  @override
  List<Object?> get props => [status, note, popRequested, errorMessage, accentOverride];
}

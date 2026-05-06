import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/models/note.dart';

enum NoteEditorStatus { initial, loading, ready, notFound, saving, error }

class NoteEditorState extends Equatable {
  const NoteEditorState({
    this.status = NoteEditorStatus.initial,
    this.note,
    this.popRequested = false,
    this.errorMessage,
    this.accentOverride,
    this.isCapturingAudio = false,
    this.currentAmplitude,
    this.committedAudioBlock,
    this.audioPermissionExplainerRequested = false,
    this.isDictating = false,
    this.dictationDraft,
    this.committedDictationText,
    this.dictationUnavailableExplainerRequested = false,
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

  /// True while a recorder session is active. Drives the pulse + amplitude
  /// meter UI on the editor's mic button.
  final bool isCapturingAudio;

  /// Latest dB-normalized amplitude sample (range [0, 1]) emitted by the
  /// recorder. `null` when not capturing.
  final double? currentAmplitude;

  /// One-shot signal: a freshly-finalized audio block. The screen consumes
  /// it via `BlocListener`, appends to its local block list, and dispatches
  /// `BlocksReplaced` to persist. Reset to `null` on the next emission.
  final AudioBlock? committedAudioBlock;

  /// One-shot signal: the OS has put microphone permission out of reach
  /// (`permanentlyDenied` / `restricted`). The screen shows the
  /// `PermissionExplainerSheet` and the next emission resets the flag.
  /// Shared by audio capture and STT — both use the same mic permission.
  final bool audioPermissionExplainerRequested;

  /// True while the speech recognizer is listening. Drives the dictation
  /// button's active-state visual and the in-block italic preview.
  final bool isDictating;

  /// Transient italic preview of the current partial recognition. `null`
  /// when not dictating; cleared via `clearDictationDraft: true` on stop /
  /// cancel.
  final String? dictationDraft;

  /// One-shot signal: a non-empty final transcription ready to commit. The
  /// screen consumes it via `BlocListener`, appends to the last text block
  /// (or creates one), and dispatches `BlocksReplaced` to persist. Reset to
  /// `null` on the next emission. Mirrors [committedAudioBlock].
  final String? committedDictationText;

  /// One-shot signal: the device cannot run STT fully offline (capability
  /// probe returned false). The screen shows an explainer sheet and the
  /// next emission resets the flag.
  final bool dictationUnavailableExplainerRequested;

  NoteEditorState copyWith({
    NoteEditorStatus? status,
    Note? note,
    bool? popRequested,
    String? errorMessage,
    bool clearError = false,
    String? accentOverride,
    bool clearAccentOverride = false,
    bool? isCapturingAudio,
    double? currentAmplitude,
    bool clearAmplitude = false,
    AudioBlock? committedAudioBlock,
    bool? audioPermissionExplainerRequested,
    bool? isDictating,
    String? dictationDraft,
    bool clearDictationDraft = false,
    String? committedDictationText,
    bool? dictationUnavailableExplainerRequested,
  }) {
    return NoteEditorState(
      status: status ?? this.status,
      note: note ?? this.note,
      popRequested: popRequested ?? false,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      accentOverride: clearAccentOverride ? null : (accentOverride ?? this.accentOverride),
      isCapturingAudio: isCapturingAudio ?? this.isCapturingAudio,
      currentAmplitude: clearAmplitude ? null : (currentAmplitude ?? this.currentAmplitude),
      // One-shot: defaults to null on every emission unless the caller
      // explicitly sets it. Mirrors the [popRequested] pattern.
      committedAudioBlock: committedAudioBlock,
      audioPermissionExplainerRequested: audioPermissionExplainerRequested ?? false,
      isDictating: isDictating ?? this.isDictating,
      dictationDraft: clearDictationDraft ? null : (dictationDraft ?? this.dictationDraft),
      // One-shot: same pattern as [committedAudioBlock].
      committedDictationText: committedDictationText,
      dictationUnavailableExplainerRequested: dictationUnavailableExplainerRequested ?? false,
    );
  }

  @override
  List<Object?> get props => [
        status,
        note,
        popRequested,
        errorMessage,
        accentOverride,
        isCapturingAudio,
        currentAmplitude,
        committedAudioBlock,
        audioPermissionExplainerRequested,
        isDictating,
        dictationDraft,
        committedDictationText,
        dictationUnavailableExplainerRequested,
      ];
}

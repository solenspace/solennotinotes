import 'package:bloc/bloc.dart';
import 'package:characters/characters.dart';
import 'package:noti_notes_app/features/note_editor/notification_id.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity_overlay.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens/color_tokens.dart';
import 'package:uuid/uuid.dart';

import 'note_editor_event.dart';
import 'note_editor_state.dart';

typedef CancelNotification = void Function(int id);

/// Per-route BLoC owning a single note's editing session. Mounted by
/// `BlocProvider.create` in `NoteEditorScreen` and disposed when the route
/// pops. Per-action persistence: every handler awaits `repository.save`
/// (or `delete`) before emitting state — same I/O profile as the legacy
/// [Notes] provider's `tooling*` methods.
class NoteEditorBloc extends Bloc<NoteEditorEvent, NoteEditorState> {
  NoteEditorBloc({
    required NotesRepository repository,
    required NotiIdentityRepository identityRepository,
    ImagePickerService? imageService,
    CancelNotification? cancelNotification,
  })  : _repository = repository,
        _identityRepository = identityRepository,
        _imageService = imageService ?? const ImagePickerService(),
        _cancelNotification = cancelNotification ?? LocalNotificationService.cancelNotification,
        super(const NoteEditorState()) {
    on<EditorOpened>(_onEditorOpened);
    on<TitleChanged>(_onTitleChanged);
    on<BlocksReplaced>(_onBlocksReplaced);
    on<TagAdded>(_onTagAdded);
    on<TagRemovedAtIndex>(_onTagRemovedAtIndex);
    on<ImageSelected>(_onImageSelected);
    on<ImageRemoved>(_onImageRemoved);
    on<OverlayPaletteChanged>(_onOverlayPaletteChanged);
    on<OverlayPatternChanged>(_onOverlayPatternChanged);
    on<OverlayAccentChanged>(_onOverlayAccentChanged);
    on<OverlayResetToIdentityDefault>(_onOverlayResetToIdentityDefault);
    on<OverlayConvertToMine>(_onOverlayConvertToMine);
    // ignore: deprecated_member_use_from_same_package
    on<BackgroundColorChanged>(_onBackgroundColorChanged);
    // ignore: deprecated_member_use_from_same_package
    on<PatternImageSet>(_onPatternImageSet);
    // ignore: deprecated_member_use_from_same_package
    on<PatternImageRemoved>(_onPatternImageRemoved);
    // ignore: deprecated_member_use_from_same_package
    on<FontColorChanged>(_onFontColorChanged);
    on<DisplayModeChanged>(_onDisplayModeChanged);
    // ignore: deprecated_member_use_from_same_package
    on<GradientChanged>(_onGradientChanged);
    // ignore: deprecated_member_use_from_same_package
    on<GradientToggled>(_onGradientToggled);
    on<ReminderSet>(_onReminderSet);
    on<ReminderRemoved>(_onReminderRemoved);
    on<TaskAdded>(_onTaskAdded);
    on<TaskToggledAtIndex>(_onTaskToggledAtIndex);
    on<TaskRemovedAtIndex>(_onTaskRemovedAtIndex);
    on<TaskContentUpdatedAtIndex>(_onTaskContentUpdatedAtIndex);
    on<PinToggled>(_onPinToggled);
    on<NoteDeleted>(_onNoteDeleted);
  }

  final NotesRepository _repository;
  final NotiIdentityRepository _identityRepository;
  final ImagePickerService _imageService;
  final CancelNotification _cancelNotification;

  Future<void> _onEditorOpened(
    EditorOpened event,
    Emitter<NoteEditorState> emit,
  ) async {
    emit(state.copyWith(status: NoteEditorStatus.loading, clearError: true));
    if (event.noteId == null) {
      emit(state.copyWith(status: NoteEditorStatus.ready, note: _blankNote(event.noteType)));
      return;
    }
    final all = await _repository.getAll();
    final found = _firstWhereOrNull(all, (n) => n.id == event.noteId);
    if (found == null) {
      emit(state.copyWith(status: NoteEditorStatus.notFound));
      return;
    }
    emit(state.copyWith(status: NoteEditorStatus.ready, note: found));
  }

  Future<void> _onTitleChanged(
    TitleChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.title = event.title;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onBlocksReplaced(
    BlocksReplaced event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.blocks = event.blocks;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTagAdded(
    TagAdded event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.tags.add(event.tag);
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTagRemovedAtIndex(
    TagRemovedAtIndex event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    if (event.index < 0 || event.index >= note.tags.length) return;
    note.tags.remove(note.tags.elementAt(event.index));
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onImageSelected(
    ImageSelected event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final old = note.imageFile;
    if (old != null && old.path != event.file.path) {
      await _imageService.removeImage(old);
    }
    note.imageFile = event.file;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onImageRemoved(
    ImageRemoved event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final old = note.imageFile;
    if (old != null) {
      await _imageService.removeImage(old);
    }
    note.imageFile = null;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onOverlayPaletteChanged(
    OverlayPaletteChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.colorBackground = event.overlay.surface;
    note.fontColor = event.overlay.onSurface ?? clampForReadability(event.overlay.surface);
    note.gradient = null;
    note.hasGradient = false;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onOverlayPatternChanged(
    OverlayPatternChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.patternImage = event.patternKey?.name;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onOverlayAccentChanged(
    OverlayAccentChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    if (state.note == null) return;
    final raw = event.accent;
    if (raw == null || raw.isEmpty) {
      emit(state.copyWith(clearAccentOverride: true));
      return;
    }
    // Constrain to a single user-perceived character (grapheme cluster).
    final firstGrapheme = raw.characters.isEmpty ? null : raw.characters.first;
    if (firstGrapheme == null) {
      emit(state.copyWith(clearAccentOverride: true));
      return;
    }
    emit(state.copyWith(accentOverride: firstGrapheme));
  }

  Future<void> _onOverlayResetToIdentityDefault(
    OverlayResetToIdentityDefault event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final identity = await _identityRepository.getCurrent();
    final identityOverlay = identity.toOverlay();
    _writeOverlay(note, identityOverlay);
    await _repository.save(note);
    emit(
      state.copyWith(
        note: note,
        accentOverride: identityOverlay.signatureAccent,
        clearAccentOverride: identityOverlay.signatureAccent == null,
      ),
    );
  }

  Future<void> _onOverlayConvertToMine(
    OverlayConvertToMine event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final identity = await _identityRepository.getCurrent();
    final identityOverlay = identity.toOverlay();
    _writeOverlay(note, identityOverlay);
    // `fromIdentityId` lives on NotiThemeOverlay, not the legacy Note schema,
    // so there's nothing to clear on disk yet — Spec 04b promotes it to a
    // first-class column. The chip's render gate already keys off the
    // synthesized overlay, which now has fromIdentityId == null because
    // legacy notes never carry one.
    await _repository.save(note);
    emit(
      state.copyWith(
        note: note,
        accentOverride: identityOverlay.signatureAccent,
        clearAccentOverride: identityOverlay.signatureAccent == null,
      ),
    );
  }

  /// Writes the parts of [overlay] that have a home in the legacy schema.
  /// `signatureTagline`, `signatureAccent`, and `fromIdentityId` are
  /// in-memory-only on legacy notes (see [NoteEditorState.accentOverride]).
  void _writeOverlay(Note note, NotiThemeOverlay overlay) {
    note.colorBackground = overlay.surface;
    note.fontColor = overlay.onSurface ?? clampForReadability(overlay.surface);
    note.gradient = null;
    note.hasGradient = false;
    note.patternImage = overlay.patternKey?.name;
  }

  Future<void> _onBackgroundColorChanged(
    BackgroundColorChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.colorBackground = event.color;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onPatternImageSet(
    PatternImageSet event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.patternImage = event.patternKey;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onPatternImageRemoved(
    PatternImageRemoved event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.patternImage = null;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onFontColorChanged(
    FontColorChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.fontColor = event.color;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onDisplayModeChanged(
    DisplayModeChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.displayMode = event.mode;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onGradientChanged(
    GradientChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.gradient = event.gradient;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onGradientToggled(
    GradientToggled event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.hasGradient = !note.hasGradient;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onReminderSet(
    ReminderSet event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.reminder = event.dateTime;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onReminderRemoved(
    ReminderRemoved event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.reminder = null;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTaskAdded(
    TaskAdded event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.todoList.add(<String, dynamic>{'content': '', 'isChecked': false});
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTaskToggledAtIndex(
    TaskToggledAtIndex event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    if (event.index < 0 || event.index >= note.todoList.length) return;
    final current = note.todoList[event.index]['isChecked'] as bool? ?? false;
    note.todoList[event.index]['isChecked'] = !current;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTaskRemovedAtIndex(
    TaskRemovedAtIndex event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    if (event.index < 0 || event.index >= note.todoList.length) return;
    note.todoList.removeAt(event.index);
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onTaskContentUpdatedAtIndex(
    TaskContentUpdatedAtIndex event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    if (event.index < 0 || event.index >= note.todoList.length) return;
    note.todoList[event.index]['content'] = event.content;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onPinToggled(
    PinToggled event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.isPinned = !note.isPinned;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onNoteDeleted(
    NoteDeleted event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    _cancelNotification(notificationIdForNote(note.id));
    await _repository.delete(note.id);
    emit(state.copyWith(popRequested: true));
  }

  Note _blankNote(NoteType type) {
    return Note(
      <String>{},
      null,
      null,
      type == NoteType.todo
          ? <Map<String, dynamic>>[
              <String, dynamic>{'content': '', 'isChecked': false},
            ]
          : <Map<String, dynamic>>[],
      null,
      null,
      id: const Uuid().v4(),
      title: '',
      content: '',
      dateCreated: DateTime.now(),
      colorBackground: NotesColorPalette.defaultSwatch.light,
      fontColor: NotiColors.bone.inkOnLightSurface,
      hasGradient: false,
      displayMode: type == NoteType.todo ? DisplayMode.withTodoList : DisplayMode.normal,
    );
  }
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

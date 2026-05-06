import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:characters/characters.dart';
import 'package:noti_notes_app/features/note_editor/notification_id.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity_overlay.dart';
import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/services/speech/stt_models.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';
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
    required AudioRepository audio,
    required PermissionsService permissions,
    required SttService stt,
    ImagePickerService? imageService,
    CancelNotification? cancelNotification,
  })  : _repository = repository,
        _identityRepository = identityRepository,
        _audio = audio,
        _permissions = permissions,
        _stt = stt,
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
    on<AudioCaptureRequested>(_onAudioCaptureRequested);
    on<AudioCaptureStopped>(_onAudioCaptureStopped);
    on<AudioCaptureCancelled>(_onAudioCaptureCancelled);
    on<AudioBlockRemoved>(_onAudioBlockRemoved);
    on<AudioAmplitudeSampled>(_onAudioAmplitudeSampled);
    on<DictationStarted>(_onDictationStarted);
    on<DictationStopped>(_onDictationStopped);
    on<DictationCancelled>(_onDictationCancelled);
    on<DictationPartialEmitted>(_onDictationPartialEmitted);
    on<DictationFinalEmitted>(_onDictationFinalEmitted);
  }

  final NotesRepository _repository;
  final NotiIdentityRepository _identityRepository;
  final AudioRepository _audio;
  final PermissionsService _permissions;
  final SttService _stt;
  final ImagePickerService _imageService;
  final CancelNotification _cancelNotification;

  AudioCaptureSession? _activeAudioSession;
  StreamSubscription<double>? _amplitudeSub;

  StreamSubscription<SttRecognitionEvent>? _dictationSub;

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

  Future<void> _onAudioCaptureRequested(
    AudioCaptureRequested event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null || _activeAudioSession != null) return;

    final status = await _permissions.microphoneStatus();
    if (status.isFinalDenial) {
      emit(state.copyWith(audioPermissionExplainerRequested: true));
      return;
    }
    if (!status.isUsable) {
      final result = await _permissions.requestMicrophone();
      if (!result.isUsable) {
        if (result.isFinalDenial) {
          emit(state.copyWith(audioPermissionExplainerRequested: true));
        } else {
          // Two-emission snackbar pattern: set the message so
          // `BlocListener<errorMessage>` fires, then clear so the next
          // denial (same message text) still produces a null→non-null
          // transition and re-fires the listener.
          emit(state.copyWith(errorMessage: 'Microphone permission needed to record.'));
          emit(state.copyWith(clearError: true));
        }
        return;
      }
    }

    final session = await _audio.startCapture(noteId: note.id);
    _activeAudioSession = session;
    emit(state.copyWith(isCapturingAudio: true, currentAmplitude: 0));

    await _amplitudeSub?.cancel();
    _amplitudeSub = _audio.amplitudeStream(session).listen(
      (amp) {
        if (isClosed) return;
        add(AudioAmplitudeSampled(amp));
      },
      // Native audio sessions can be interrupted (incoming call on iOS,
      // audio focus loss on Android). Treat as cancel — discarding a
      // partial recording is safer than trying to finalize a possibly
      // corrupt file. The user can re-tap to record again.
      onError: (Object _, StackTrace __) {
        if (!isClosed) add(const AudioCaptureCancelled());
      },
      cancelOnError: true,
    );
  }

  Future<void> _onAudioAmplitudeSampled(
    AudioAmplitudeSampled event,
    Emitter<NoteEditorState> emit,
  ) async {
    if (!state.isCapturingAudio) return;
    emit(state.copyWith(currentAmplitude: event.amplitude));
  }

  Future<void> _onAudioCaptureStopped(
    AudioCaptureStopped event,
    Emitter<NoteEditorState> emit,
  ) async {
    final session = _activeAudioSession;
    if (session == null) return;

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final block = await _audio.finalize(session);
    _activeAudioSession = null;

    // One-shot: the screen consumes [committedAudioBlock] via BlocListener,
    // appends to its local block list, and dispatches BlocksReplaced —
    // mirrors the image-block flow. The bloc never mutates note.blocks.
    emit(
      state.copyWith(
        isCapturingAudio: false,
        committedAudioBlock: block,
        clearAmplitude: true,
      ),
    );
  }

  Future<void> _onAudioCaptureCancelled(
    AudioCaptureCancelled event,
    Emitter<NoteEditorState> emit,
  ) async {
    final session = _activeAudioSession;
    if (session == null) return;

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _audio.cancel(session);
    _activeAudioSession = null;

    emit(state.copyWith(isCapturingAudio: false, clearAmplitude: true));
  }

  Future<void> _onAudioBlockRemoved(
    AudioBlockRemoved event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    await _audio.delete(noteId: note.id, audioId: event.audioId);
  }

  Future<void> _onDictationStarted(
    DictationStarted event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null || state.isDictating) return;

    if (!_stt.isOfflineCapable) {
      emit(state.copyWith(dictationUnavailableExplainerRequested: true));
      return;
    }

    final status = await _permissions.microphoneStatus();
    if (status.isFinalDenial) {
      emit(state.copyWith(audioPermissionExplainerRequested: true));
      return;
    }
    if (!status.isUsable) {
      final result = await _permissions.requestMicrophone();
      if (!result.isUsable) {
        if (result.isFinalDenial) {
          emit(state.copyWith(audioPermissionExplainerRequested: true));
        } else {
          // Two-emission snackbar pattern (see _onAudioCaptureRequested).
          emit(state.copyWith(errorMessage: 'Microphone permission needed to dictate.'));
          emit(state.copyWith(clearError: true));
        }
        return;
      }
    }

    await _dictationSub?.cancel();
    _dictationSub = _stt.startDictation().listen(
      (recognition) {
        if (isClosed) return;
        switch (recognition) {
          case SttPartialResult(:final text):
            add(DictationPartialEmitted(text));
          case SttFinalResult(:final text, :final confidence):
            add(DictationFinalEmitted(text: text, confidence: confidence));
        }
      },
      // Recognizer errors (audio session preempted, recognizer service
      // crashed, etc.) discard the in-flight session — same conservative
      // policy as audio capture.
      onError: (Object _, StackTrace __) {
        if (!isClosed) add(const DictationCancelled());
      },
      cancelOnError: true,
    );

    emit(state.copyWith(isDictating: true, dictationDraft: ''));
  }

  Future<void> _onDictationStopped(
    DictationStopped event,
    Emitter<NoteEditorState> emit,
  ) async {
    if (!state.isDictating) return;
    // The recognizer will emit one trailing final result; the listener
    // routes it through DictationFinalEmitted, which clears state and
    // surfaces the committedDictationText one-shot.
    await _stt.stop();
  }

  Future<void> _onDictationCancelled(
    DictationCancelled event,
    Emitter<NoteEditorState> emit,
  ) async {
    if (!state.isDictating && _dictationSub == null) return;
    await _dictationSub?.cancel();
    _dictationSub = null;
    await _stt.cancel();
    emit(state.copyWith(isDictating: false, clearDictationDraft: true));
  }

  Future<void> _onDictationPartialEmitted(
    DictationPartialEmitted event,
    Emitter<NoteEditorState> emit,
  ) async {
    if (!state.isDictating) return;
    emit(state.copyWith(dictationDraft: event.text));
  }

  Future<void> _onDictationFinalEmitted(
    DictationFinalEmitted event,
    Emitter<NoteEditorState> emit,
  ) async {
    await _dictationSub?.cancel();
    _dictationSub = null;
    final trimmed = event.text.trim();
    emit(
      state.copyWith(
        isDictating: false,
        clearDictationDraft: true,
        // One-shot: only set when the recognizer produced something. An
        // empty result (e.g. offline-incapable defence-in-depth path or
        // a stopped session that captured no speech) leaves the field
        // null so the screen does not append blank text.
        committedDictationText: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final session = _activeAudioSession;
    if (session != null) {
      _activeAudioSession = null;
      await _audio.cancel(session);
    }
    await _dictationSub?.cancel();
    _dictationSub = null;
    if (_stt.isListening) {
      await _stt.cancel();
    }
    return super.close();
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

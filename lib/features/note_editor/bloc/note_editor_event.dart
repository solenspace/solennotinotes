import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

sealed class NoteEditorEvent extends Equatable {
  const NoteEditorEvent();

  @override
  List<Object?> get props => const [];
}

/// Mounted by the screen's BlocProvider.create.
/// `noteId == null` means "create a new note"; non-null means "load and
/// edit existing". `noteType` only applies when `noteId == null`.
final class EditorOpened extends NoteEditorEvent {
  const EditorOpened({this.noteId, this.noteType = NoteType.content});
  final String? noteId;
  final NoteType noteType;
  @override
  List<Object?> get props => [noteId, noteType];
}

// — Title and content —

final class TitleChanged extends NoteEditorEvent {
  const TitleChanged(this.title);
  final String title;
  @override
  List<Object?> get props => [title];
}

final class BlocksReplaced extends NoteEditorEvent {
  const BlocksReplaced(this.blocks);
  final List<Map<String, dynamic>> blocks;
  @override
  List<Object?> get props => [blocks];
}

// — Tags —

final class TagAdded extends NoteEditorEvent {
  const TagAdded(this.tag);
  final String tag;
  @override
  List<Object?> get props => [tag];
}

final class TagRemovedAtIndex extends NoteEditorEvent {
  const TagRemovedAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

// — Image —

final class ImageSelected extends NoteEditorEvent {
  const ImageSelected(this.file);
  final File file;
  @override
  List<Object?> get props => [file.path];
}

final class ImageRemoved extends NoteEditorEvent {
  const ImageRemoved();
}

// — Theme / appearance —

/// Picks a curated or custom palette for the active note. Carries the full
/// [NotiThemeOverlay] so the handler can write surface, surfaceVariant,
/// accent, and onAccent in one shot.
final class OverlayPaletteChanged extends NoteEditorEvent {
  const OverlayPaletteChanged(this.overlay);
  final NotiThemeOverlay overlay;
  @override
  List<Object?> get props => [overlay];
}

/// Sets or clears the per-note pattern. Null = pattern removed.
final class OverlayPatternChanged extends NoteEditorEvent {
  const OverlayPatternChanged(this.patternKey);
  final NotiPatternKey? patternKey;
  @override
  List<Object?> get props => [patternKey];
}

/// Updates the per-note signature accent glyph. Null = remove glyph.
/// The glyph is stored in [NoteEditorState.accentOverride] until Spec 04b
/// promotes it to a first-class column on [Note].
final class OverlayAccentChanged extends NoteEditorEvent {
  const OverlayAccentChanged(this.accent);
  final String? accent;
  @override
  List<Object?> get props => [accent];
}

/// Resets the active note's overlay to the user's [NotiIdentity] default.
/// Long-press on the editor toolbar's paintbrush dispatches this.
final class OverlayResetToIdentityDefault extends NoteEditorEvent {
  const OverlayResetToIdentityDefault();
}

/// Replaces a received note's overlay with the current user's identity
/// overlay and clears [NotiThemeOverlay.fromIdentityId]. Wired to the
/// "Convert to mine" item in the from-sender chip's popup menu.
final class OverlayConvertToMine extends NoteEditorEvent {
  const OverlayConvertToMine();
}

@Deprecated('use OverlayPaletteChanged; remove in spec 04b')
final class BackgroundColorChanged extends NoteEditorEvent {
  const BackgroundColorChanged(this.color);
  final Color color;
  @override
  List<Object?> get props => [color];
}

@Deprecated('use OverlayPatternChanged; remove in spec 04b')
final class PatternImageSet extends NoteEditorEvent {
  const PatternImageSet(this.patternKey);
  final String patternKey;
  @override
  List<Object?> get props => [patternKey];
}

@Deprecated('use OverlayPatternChanged with null patternKey; remove in spec 04b')
final class PatternImageRemoved extends NoteEditorEvent {
  const PatternImageRemoved();
}

@Deprecated('use OverlayPaletteChanged; remove in spec 04b')
final class FontColorChanged extends NoteEditorEvent {
  const FontColorChanged(this.color);
  final Color color;
  @override
  List<Object?> get props => [color];
}

final class DisplayModeChanged extends NoteEditorEvent {
  const DisplayModeChanged(this.mode);
  final DisplayMode mode;
  @override
  List<Object?> get props => [mode];
}

@Deprecated('use OverlayPaletteChanged; remove in spec 04b')
final class GradientChanged extends NoteEditorEvent {
  const GradientChanged(this.gradient);
  final LinearGradient gradient;
  @override
  List<Object?> get props => [gradient];
}

@Deprecated('use OverlayPaletteChanged; remove in spec 04b')
final class GradientToggled extends NoteEditorEvent {
  const GradientToggled();
}

// — Reminder —

final class ReminderSet extends NoteEditorEvent {
  const ReminderSet(this.dateTime);
  final DateTime dateTime;
  @override
  List<Object?> get props => [dateTime];
}

final class ReminderRemoved extends NoteEditorEvent {
  const ReminderRemoved();
}

// — Todos —

final class TaskAdded extends NoteEditorEvent {
  const TaskAdded();
}

final class TaskToggledAtIndex extends NoteEditorEvent {
  const TaskToggledAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

final class TaskRemovedAtIndex extends NoteEditorEvent {
  const TaskRemovedAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

final class TaskContentUpdatedAtIndex extends NoteEditorEvent {
  const TaskContentUpdatedAtIndex({required this.index, required this.content});
  final int index;
  final String content;
  @override
  List<Object?> get props => [index, content];
}

// — Audio capture —

/// Long-press start (or tap-to-toggle on) on the editor's mic button.
/// The bloc gates the actual recorder start on a microphone permission
/// check; if permission is unavailable an error or explainer-sheet flag
/// is emitted instead.
final class AudioCaptureRequested extends NoteEditorEvent {
  const AudioCaptureRequested();
}

/// Long-press release (or second tap) on the mic button. The bloc
/// finalizes the active capture session into an [AudioBlock] and surfaces
/// it as a one-shot `committedAudioBlock` signal in state — the screen
/// owns the actual `note.blocks` mutation, mirroring the image-block flow.
final class AudioCaptureStopped extends NoteEditorEvent {
  const AudioCaptureStopped();
}

/// Slide-to-cancel during a hold-to-record gesture. Discards the temp
/// file and resets capture state without producing a block.
final class AudioCaptureCancelled extends NoteEditorEvent {
  const AudioCaptureCancelled();
}

/// Removes the on-disk audio asset for [audioId]. The screen separately
/// removes the block from its local list and dispatches [BlocksReplaced]
/// — this event is file-lifecycle only.
final class AudioBlockRemoved extends NoteEditorEvent {
  const AudioBlockRemoved(this.audioId);
  final String audioId;
  @override
  List<Object?> get props => [audioId];
}

/// Internal: bridges the recorder's amplitude `Stream<double>` into the
/// bloc's event loop. The listener fires after `_onAudioCaptureRequested`
/// has already returned, so its `Emitter` is closed; dispatching a fresh
/// event lets the bloc emit a new state via the standard handler path.
final class AudioAmplitudeSampled extends NoteEditorEvent {
  const AudioAmplitudeSampled(this.amplitude);
  final double amplitude;
  @override
  List<Object?> get props => [amplitude];
}

// — Pin / delete —

final class PinToggled extends NoteEditorEvent {
  const PinToggled();
}

final class NoteDeleted extends NoteEditorEvent {
  const NoteDeleted();
}

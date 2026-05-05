import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/models/note.dart';

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

final class BackgroundColorChanged extends NoteEditorEvent {
  const BackgroundColorChanged(this.color);
  final Color color;
  @override
  List<Object?> get props => [color];
}

final class PatternImageSet extends NoteEditorEvent {
  const PatternImageSet(this.patternKey);
  final String patternKey;
  @override
  List<Object?> get props => [patternKey];
}

final class PatternImageRemoved extends NoteEditorEvent {
  const PatternImageRemoved();
}

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

final class GradientChanged extends NoteEditorEvent {
  const GradientChanged(this.gradient);
  final LinearGradient gradient;
  @override
  List<Object?> get props => [gradient];
}

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

// — Pin / delete —

final class PinToggled extends NoteEditorEvent {
  const PinToggled();
}

final class NoteDeleted extends NoteEditorEvent {
  const NoteDeleted();
}

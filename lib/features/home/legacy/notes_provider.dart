import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:string_similarity/string_similarity.dart';

enum ToolingNote {
  addTag,
  removeTag,
  addImage,
  removeImage,
  color,
  patternImage,
  removePatternImage,
  addreminder,
  removeReminder,
  fontColor,
  displayMode,
  gradient,
}

class Notes with ChangeNotifier {
  Notes({
    required NotesRepository repository,
    ImagePickerService imageService = const ImagePickerService(),
  })  : _repository = repository,
        _imageService = imageService;

  final NotesRepository _repository;
  final ImagePickerService _imageService;

  final List<Note> _notes = [];
  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  bool editMode = false;
  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  Set<String> notesToDelete = {};

  List<Note> get notes {
    return [..._notes];
  }

  int get notesCount {
    return _notes.length;
  }

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  bool get isEditMode {
    // ignore: deprecated_member_use_from_same_package
    return editMode;
  }

  Future<void> clearBox() => _repository.clear();

  //? Modes on note editing

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  void activateEditMode() {
    // ignore: deprecated_member_use_from_same_package
    editMode = true;
    notifyListeners();
  }

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  void deactivateEditMode() {
    // ignore: deprecated_member_use_from_same_package
    editMode = false;
    notifyListeners();
  }

  //? Load all notes from database

  Future<void> loadNotesFromDataBase() async {
    _notes
      ..clear()
      ..addAll(await _repository.getAll());
    notifyListeners();
  }

  //?  Sort notes by date created

  void sortByDateCreated() {
    _notes.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    notifyListeners();
  }

  //? Update database

  Future<void> updateNoteOnDataBase(Note note) => _repository.save(note);

  void updateNotesOnDataBase(List<Note> notes) {
    for (var note in notes) {
      updateNoteOnDataBase(note);
    }
  }

  //? Note creation

  void addNote(Note note) {
    if (note.id.isEmpty) {
      return;
    }
    _notes.add(note);
    updateNoteOnDataBase(note);
  }

  //? Note Searching

  Note findById(String id) {
    return _notes.firstWhere((note) => note.id == id);
  }

  Note? findByIdOrNull(String id) {
    return _notes.firstWhereOrNull((note) => note.id == id);
  }

  int findIndex(String id) {
    return _notes.indexWhere((note) => note.id == id);
  }

  //? Note deletion

  Future<void> removeSelectedNotes(Set<String> ids) async {
    for (var id in ids) {
      LocalNotificationService.cancelNotification(findIndex(id));
      _notes.removeWhere((note) => note.id == id);
      await _repository.delete(id);
    }
    notifyListeners();
  }

  //? Note Updating for temporal memory

  void updateNote(
    Note noteUpdated,
  ) {
    final noteIndex = findIndex(noteUpdated.id);
    if (noteIndex >= 0) {
      _notes[noteIndex] = noteUpdated;
      updateNoteOnDataBase(noteUpdated);
      notifyListeners();
    }
  }

  //? Filtering methods

  List<Note> filterByTitle(String name) {
    return _notes
        .where(
          (note) => note.title.toUpperCase().similarityTo(name.toUpperCase()) > 0.6 ? true : false,
        )
        .toList();
  }

  List<Note> filterByTag(Set<String> tags) {
    return _notes.where((note) => note.tags.intersection(tags).isNotEmpty ? true : false).toList();
  }

  Color findColor(String id) {
    return _notes.firstWhere((note) => note.id == id).colorBackground;
  }

  Color findFontColor(String id) {
    return _notes.firstWhere((note) => note.id == id).fontColor;
  }

  String? findPatternImage(String id) {
    return _notes.firstWhereOrNull((note) => note.id == id)!.patternImage;
  }

  LinearGradient? findGradient(String id) {
    return _notes.firstWhereOrNull((note) => note.id == id)!.gradient;
  }

  //? Tooling for note changing
  // Convert to switch
  void toolingNote(
    String id,
    ToolingNote tooling,
    dynamic value, [
    int index = 0,
  ]) {
    final noteIndex = findIndex(id);

    if (noteIndex >= 0) {
      switch (tooling) {
        case ToolingNote.addImage:
          _notes[noteIndex].imageFile = File(value.path);
          break;
        case ToolingNote.removeImage:
          _imageService.removeImage(_notes[noteIndex].imageFile!);
          _notes[noteIndex].imageFile = value;
          break;
        case ToolingNote.addTag:
          _notes[noteIndex].tags.add(value);
          break;
        case ToolingNote.removeTag:
          _notes[noteIndex].tags.remove(_notes[noteIndex].tags.elementAt(index));
          break;
        case ToolingNote.color:
          _notes[noteIndex].colorBackground = value;
          break;
        case ToolingNote.patternImage:
          _notes[noteIndex].patternImage = value;
          break;
        case ToolingNote.removePatternImage:
          _notes[noteIndex].patternImage = null;
          break;
        case ToolingNote.fontColor:
          _notes[noteIndex].fontColor = value;
          break;
        case ToolingNote.displayMode:
          _notes[noteIndex].displayMode = value;
          break;
        case ToolingNote.addreminder:
          _notes[noteIndex].reminder = value;
          break;
        case ToolingNote.removeReminder:
          _notes[noteIndex].reminder = null;
          break;
        case ToolingNote.gradient:
          _notes[noteIndex].gradient = value;
          break;
      }

      updateNoteOnDataBase(_notes[noteIndex]);
      notifyListeners();
    }
  }

  void addImageToNote(String id, File? image) {
    toolingNote(
      id,
      ToolingNote.addImage,
      image,
    );
  }

  void removeImageFromNote(String id) {
    toolingNote(
      id,
      ToolingNote.removeImage,
      null,
    );
  }

  void addTagToNote(String tag, String id) {
    toolingNote(
      id,
      ToolingNote.addTag,
      tag,
    );
  }

  void removeTagsFromNote(int index, String id) {
    toolingNote(
      id,
      ToolingNote.removeTag,
      null,
      index,
    );
  }

  void changeCurrentColor(String id, Color color) {
    toolingNote(
      id,
      ToolingNote.color,
      color,
    );
  }

  void changeCurrentPattern(String id, String? pattern) {
    toolingNote(
      id,
      ToolingNote.patternImage,
      pattern,
    );
  }

  void removeCurrentPattern(String id) {
    toolingNote(
      id,
      ToolingNote.removePatternImage,
      null,
    );
  }

  void changeCurrentFontColor(String id, Color color) {
    toolingNote(
      id,
      ToolingNote.fontColor,
      color,
    );
  }

  void changeCurrentDisplay(String id, DisplayMode mode) {
    toolingNote(
      id,
      ToolingNote.displayMode,
      mode,
    );
  }

  void changeCurrentGradient(String id, LinearGradient gradient) {
    toolingNote(
      id,
      ToolingNote.gradient,
      gradient,
    );
  }

  void addReminder(String id, DateTime dateTime) {
    toolingNote(
      id,
      ToolingNote.addreminder,
      dateTime,
    );
  }

  void removeReminder(String id) {
    toolingNote(
      id,
      ToolingNote.removeReminder,
      null,
    );
  }

  void toggleTask(String id, int index) {
    final noteIndex = findIndex(id);
    if (noteIndex >= 0) {
      _notes[noteIndex].todoList[index]['isChecked'] =
          !_notes[noteIndex].todoList[index]['isChecked'];
      updateNoteOnDataBase(_notes[noteIndex]);
      notifyListeners();
    }
  }

  void addTask(String id) {
    final noteIndex = findIndex(id);
    if (noteIndex >= 0) {
      _notes[noteIndex].todoList.add({
        'content': '',
        'isChecked': false,
      });
      updateNoteOnDataBase(_notes[noteIndex]);
      notifyListeners();
    }
  }

  void removeTask(String id, int index) {
    final noteIndex = findIndex(id);
    if (noteIndex >= 0) {
      _notes[noteIndex].todoList.removeAt(index);
      updateNoteOnDataBase(_notes[noteIndex]);
      notifyListeners();
    }
  }

  void updateTask(String id, int index, String content) {
    final noteIndex = findIndex(id);
    if (noteIndex >= 0) {
      _notes[noteIndex].todoList[index]['content'] = content;
      updateNoteOnDataBase(_notes[noteIndex]);
      notifyListeners();
    }
  }

  bool checkGradient(String id) {
    return findById(id).hasGradient;
  }

  void switchGradient(String id) {
    findById(id).hasGradient = !findById(id).hasGradient;
    updateNoteOnDataBase(findById(id));
    notifyListeners();
  }

  //? Pinning

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  List<Note> get pinnedNotes => _notes.where((n) => n.isPinned).toList();
  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  List<Note> get unpinnedNotes => _notes.where((n) => !n.isPinned).toList();

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  void togglePin(String id) {
    final i = findIndex(id);
    if (i < 0) return;
    _notes[i].isPinned = !_notes[i].isPinned;
    updateNoteOnDataBase(_notes[i]);
    notifyListeners();
  }

  //? Block-based editor mutations (used by the unified editor)

  void replaceBlocks(String id, List<Map<String, dynamic>> blocks) {
    final i = findIndex(id);
    if (i < 0) return;
    _notes[i].blocks = blocks;
    updateNoteOnDataBase(_notes[i]);
    notifyListeners();
  }

  void updateTitle(String id, String title) {
    final i = findIndex(id);
    if (i < 0) return;
    _notes[i].title = title;
    updateNoteOnDataBase(_notes[i]);
    notifyListeners();
  }

  @Deprecated('migrated to NotesListBloc; remove in Spec 08')
  void deleteNote(String id) {
    final i = findIndex(id);
    if (i < 0) return;
    LocalNotificationService.cancelNotification(i);
    _notes.removeAt(i);
    unawaited(_repository.delete(id));
    notifyListeners();
  }

  // Co pilot did this
  Set<String> getMostUsedTags() {
    final tags = <String, int>{};
    for (var note in _notes) {
      for (var tag in note.tags) {
        if (tags.containsKey(tag)) {
          tags[tag] = tags[tag]! + 1;
        } else {
          tags[tag] = 1;
        }
      }
    }
    final mostUsedTags = tags.entries.toList();
    mostUsedTags.sort((a, b) => b.value.compareTo(a.value));
    return mostUsedTags.take(5).map((e) => e.key).toSet();
  }
}

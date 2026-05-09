import 'dart:io';

import 'package:flutter/material.dart';
import 'package:noti_notes_app/helpers/alignment.dart';

// How this works:
/*
* withTodoList: The todo list with all the contents except the image
* withImage: The image without the todo list and the content normal
* withoutContent: The image the title no content and no todo list
* normal: normal displaying without todo list and all elements
*/

enum DisplayMode { withTodoList, withImage, withoutContent, normal }

class Note {
  final String id;
  String title;
  String content;
  Set<String> tags;
  DateTime dateCreated;
  DateTime? reminder;
  File? imageFile;
  Color colorBackground;
  Color fontColor;
  String? patternImage;
  DisplayMode displayMode;
  bool hasGradient;
  LinearGradient? gradient;
  bool isPinned;
  int? sortIndex;

  /// New unified editor block list. Each block is a map with a 'type' key
  /// (one of 'text', 'checklist', 'image') plus type-specific fields.
  /// New notes use this exclusively; legacy notes use content/todoList/imageFile.
  List<Map<String, dynamic>> blocks;

  List<Map<String, dynamic>> todoList;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title.isEmpty ? '' : title,
      'content': title.isEmpty ? '' : content,
      'tags': tags.toList(),
      'dateCreated': dateCreated.toIso8601String(),
      'reminder': reminder?.toIso8601String() ?? '',
      'colorBackground': colorBackground.toARGB32(),
      'fontColor': fontColor.toARGB32(),
      'imageFile': imageFile?.path,
      'patternImage': patternImage,
      'todoList': todoList,
      'displayMode': displayMode.index,
      'hasGradient': hasGradient,
      'gradient': gradient == null
          ? ''
          : {
              'colors': gradient?.colors.map((e) => e.toARGB32()).toList(),
              'alignment': [gradient!.begin.toString(), gradient!.end.toString()],
            },
      'isPinned': isPinned,
      'sortIndex': sortIndex,
      'blocks': blocks,
    };
  }

  Note(
    this.tags,
    this.imageFile,
    this.patternImage,
    this.todoList,
    this.reminder,
    this.gradient, {
    required this.id,
    required this.title,
    required this.content,
    required this.dateCreated,
    required this.colorBackground,
    required this.fontColor,
    required this.hasGradient,
    this.displayMode = DisplayMode.normal,
    this.isPinned = false,
    this.sortIndex,
    List<Map<String, dynamic>>? blocks,
  }) : blocks = blocks ?? [];

  factory Note.fromJson(Map<String, dynamic> json) {
    final dynamic rawReminder = json['reminder'];
    final dynamic rawGradient = json['gradient'];
    final dynamic rawBlocks = json['blocks'];
    return Note(
      (json['tags'] as List).cast<String>().toSet(),
      json['imageFile'] != null ? File(json['imageFile'] as String) : null,
      json['patternImage'] as String?,
      (json['todoList'] as List).cast<Map<String, dynamic>>(),
      rawReminder != null && rawReminder != '' ? DateTime.parse(rawReminder as String) : null,
      rawGradient != null && rawGradient != ''
          ? LinearGradient(
              colors: [
                Color((rawGradient as Map)['colors'][0] as int),
                Color(rawGradient['colors'][1] as int),
              ],
              begin: toAlignment(rawGradient['alignment'][0] as String),
              end: toAlignment(rawGradient['alignment'][1] as String),
            )
          : null,
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      dateCreated: DateTime.parse(json['dateCreated'] as String),
      colorBackground: Color(json['colorBackground'] as int),
      fontColor: Color(json['fontColor'] as int),
      displayMode: DisplayMode.values[json['displayMode'] as int],
      hasGradient: json['hasGradient'] as bool,
      isPinned: (json['isPinned'] as bool?) ?? false,
      sortIndex: json['sortIndex'] as int?,
      blocks: rawBlocks != null
          ? (rawBlocks as List)
              .cast<Map<dynamic, dynamic>>()
              .map((m) => m.cast<String, dynamic>())
              .toList()
          : null,
    );
  }
}

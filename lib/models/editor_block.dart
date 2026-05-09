import 'package:uuid/uuid.dart';

/// Block kinds supported by the unified editor.
enum BlockKind { text, checklist, image, audio }

/// In-memory representation of an editor block. Each block knows how to
/// serialize itself to a Map for the Note model's `blocks` field.
sealed class EditorBlock {
  final String id;
  EditorBlock({required this.id});

  Map<String, dynamic> toMap();

  static EditorBlock fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String;
    final id = map['id'] as String? ?? const Uuid().v4();
    switch (type) {
      case 'text':
        return TextBlock(id: id, text: map['text'] as String? ?? '');
      case 'checklist':
        return ChecklistBlock(
          id: id,
          text: map['text'] as String? ?? '',
          checked: map['checked'] as bool? ?? false,
        );
      case 'image':
        return ImageBlock(id: id, path: map['path'] as String? ?? '');
      case 'audio':
        return AudioBlock(
          id: id,
          path: map['path'] as String? ?? '',
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
          amplitudePeaks:
              (map['amplitudePeaks'] as List?)?.cast<num>().map((n) => n.toDouble()).toList() ??
                  const <double>[],
          truncated: map['truncated'] as bool? ?? false,
        );
      default:
        return TextBlock(id: id);
    }
  }
}

class TextBlock extends EditorBlock {
  String text;
  TextBlock({required super.id, this.text = ''});

  @override
  Map<String, dynamic> toMap() => {'type': 'text', 'id': id, 'text': text};
}

class ChecklistBlock extends EditorBlock {
  String text;
  bool checked;
  ChecklistBlock({
    required super.id,
    this.text = '',
    this.checked = false,
  });

  @override
  Map<String, dynamic> toMap() => {
        'type': 'checklist',
        'id': id,
        'text': text,
        'checked': checked,
      };
}

class ImageBlock extends EditorBlock {
  String path;
  ImageBlock({required super.id, required this.path});

  @override
  Map<String, dynamic> toMap() => {'type': 'image', 'id': id, 'path': path};
}

/// A captured audio note. The `path` points at an `.m4a` file under
/// `<app_documents>/notes/<note_id>/audio/<id>.m4a`. `amplitudePeaks` is a
/// pre-computed 80-bucket waveform (values in [0.0, 1.0]) so renderers
/// avoid decoding the file every frame. `truncated` flags clips that
/// exceeded the 10 MB cap; FFmpeg-based hard truncation is deferred per
/// progress-tracker open question 2.
class AudioBlock extends EditorBlock {
  String path;
  int durationMs;
  List<double> amplitudePeaks;
  bool truncated;

  AudioBlock({
    required super.id,
    required this.path,
    required this.durationMs,
    required this.amplitudePeaks,
    this.truncated = false,
  });

  @override
  Map<String, dynamic> toMap() => {
        'type': 'audio',
        'id': id,
        'path': path,
        'durationMs': durationMs,
        'amplitudePeaks': amplitudePeaks,
        'truncated': truncated,
      };
}

EditorBlock newTextBlock([String text = '']) => TextBlock(id: const Uuid().v4(), text: text);

EditorBlock newChecklistBlock([String text = '']) =>
    ChecklistBlock(id: const Uuid().v4(), text: text);

EditorBlock newImageBlock(String path) => ImageBlock(id: const Uuid().v4(), path: path);

AudioBlock newAudioBlock({
  required String path,
  required int durationMs,
  required List<double> amplitudePeaks,
  bool truncated = false,
}) =>
    AudioBlock(
      id: const Uuid().v4(),
      path: path,
      durationMs: durationMs,
      amplitudePeaks: amplitudePeaks,
      truncated: truncated,
    );

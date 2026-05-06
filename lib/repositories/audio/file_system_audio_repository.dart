import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';

class FileSystemAudioRepository implements AudioRepository {
  FileSystemAudioRepository({AudioRecorder? recorder, Uuid? uuid})
      : _recorder = recorder ?? AudioRecorder(),
        _uuid = uuid ?? const Uuid();

  static const int _bitRate = 64000;
  static const int _sampleRate = 44100;
  static const int _maxBytes = 10 * 1024 * 1024;
  static const int _peakBuckets = 80;
  static const Duration _amplitudeInterval = Duration(milliseconds: 60);

  // The dB range we map onto [0, 1]: -60 dB → 0.0, 0 dB → 1.0.
  // Below -60 dB is rare for spoken voice; clamping covers silence.
  static const double _dbFloor = -60;

  final AudioRecorder _recorder;
  final Uuid _uuid;

  Future<Directory> _audioDir(String noteId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'notes', noteId, 'audio'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<AudioCaptureSession> startCapture({required String noteId}) async {
    final dir = await _audioDir(noteId);
    final id = _uuid.v4();
    final path = p.join(dir.path, '$id.m4a');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: _bitRate,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
      path: path,
    );
    return AudioCaptureSession(
      id: id,
      noteId: noteId,
      tempFilePath: path,
      startedAt: DateTime.now(),
    );
  }

  @override
  Stream<double> amplitudeStream(AudioCaptureSession session) async* {
    await for (final amp in _recorder.onAmplitudeChanged(_amplitudeInterval)) {
      final normalized = ((amp.current - _dbFloor) / (-_dbFloor)).clamp(0.0, 1.0).toDouble();
      session.amplitudePeaks.add(normalized);
      yield normalized;
    }
  }

  @override
  Future<AudioBlock> finalize(AudioCaptureSession session) async {
    final stoppedPath = await _recorder.stop();
    final path = stoppedPath ?? session.tempFilePath;
    final file = File(path);
    var truncated = false;
    if (file.existsSync() && file.lengthSync() > _maxBytes) {
      // v1: flag and trust the user to keep clips under 10 minutes. Hard
      // truncation via FFmpeg is deferred; see progress-tracker open
      // question 2.
      truncated = true;
    }
    final durationMs = DateTime.now().difference(session.startedAt).inMilliseconds;
    final peaks = _downsample(session.amplitudePeaks, _peakBuckets);
    return AudioBlock(
      id: session.id,
      path: path,
      durationMs: durationMs,
      amplitudePeaks: peaks,
      truncated: truncated,
    );
  }

  @override
  Future<void> cancel(AudioCaptureSession session) async {
    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }
    final f = File(session.tempFilePath);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<void> delete({required String noteId, required String audioId}) async {
    final dir = await _audioDir(noteId);
    final f = File(p.join(dir.path, '$audioId.m4a'));
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<File> resolveFile({required String noteId, required String audioId}) async {
    final dir = await _audioDir(noteId);
    return File(p.join(dir.path, '$audioId.m4a'));
  }

  /// Reduces an arbitrary-length amplitude buffer to [targetLength] peak
  /// values. Each output bucket holds the max of the corresponding source
  /// slice — preserves transients better than mean for visualization.
  List<double> _downsample(List<double> source, int targetLength) {
    if (source.isEmpty) return List<double>.filled(targetLength, 0.0);
    if (source.length <= targetLength) {
      return <double>[
        ...source,
        ...List<double>.filled(targetLength - source.length, 0.0),
      ];
    }
    final ratio = source.length / targetLength;
    final out = <double>[];
    for (var i = 0; i < targetLength; i++) {
      final start = (i * ratio).floor();
      final end = math.min(((i + 1) * ratio).ceil(), source.length);
      double max = 0;
      for (var j = start; j < end; j++) {
        if (source[j] > max) max = source[j];
      }
      out.add(max);
    }
    return out;
  }
}

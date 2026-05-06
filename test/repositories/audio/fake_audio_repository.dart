import 'dart:async';
import 'dart:io';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';
import 'package:uuid/uuid.dart';

/// Test double for [AudioRepository]. Records every invocation so tests
/// can assert call order without touching the recorder plugin or disk.
class FakeAudioRepository implements AudioRepository {
  FakeAudioRepository();

  /// Recorded sessions in start order.
  final List<AudioCaptureSession> startedSessions = [];

  /// AudioBlock returned by [finalize] for the next call. If null, a
  /// deterministic block is synthesized from the session.
  AudioBlock? finalizeReturn;

  /// Records (noteId, audioId) pairs passed to [delete].
  final List<({String noteId, String audioId})> deletedAssets = [];

  /// Records session ids passed to [cancel].
  final List<String> cancelledIds = [];

  /// Controllable amplitude stream. Tests can add samples after starting
  /// capture; closing the controller terminates the stream so the bloc's
  /// listener completes cleanly.
  StreamController<double> amplitudes = StreamController<double>.broadcast();

  /// Toggle to make [startCapture] throw — useful for error-path tests.
  Object? startCaptureError;

  @override
  Future<AudioCaptureSession> startCapture({required String noteId}) async {
    if (startCaptureError != null) throw startCaptureError!;
    final session = AudioCaptureSession(
      id: const Uuid().v4(),
      noteId: noteId,
      tempFilePath: '/fake/$noteId/${const Uuid().v4()}.m4a',
      startedAt: DateTime.now(),
    );
    startedSessions.add(session);
    return session;
  }

  @override
  Stream<double> amplitudeStream(AudioCaptureSession session) => amplitudes.stream;

  @override
  Future<AudioBlock> finalize(AudioCaptureSession session) async {
    final preset = finalizeReturn;
    if (preset != null) return preset;
    return AudioBlock(
      id: session.id,
      path: session.tempFilePath,
      durationMs: 1000,
      amplitudePeaks: const <double>[0.1, 0.5, 0.9],
    );
  }

  @override
  Future<void> cancel(AudioCaptureSession session) async {
    cancelledIds.add(session.id);
  }

  @override
  Future<void> delete({required String noteId, required String audioId}) async {
    deletedAssets.add((noteId: noteId, audioId: audioId));
  }

  @override
  Future<File> resolveFile({required String noteId, required String audioId}) async {
    return File('/fake/$noteId/$audioId.m4a');
  }

  Future<void> dispose() => amplitudes.close();
}

import 'dart:io';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';

/// Owns the audio capture and on-disk lifecycle for note audio assets.
/// Per architecture invariants 5 (Hive writes flow through repos) and 7
/// (audio blobs live on disk), no other layer touches `<docs>/notes/.../audio/`.
abstract class AudioRepository {
  /// Allocates an asset id, ensures the per-note audio directory exists,
  /// starts the recorder, and returns a session pinned to the destination
  /// path. The session is the only handle for [amplitudeStream], [finalize],
  /// and [cancel].
  Future<AudioCaptureSession> startCapture({required String noteId});

  /// Emits dB-normalized samples (range [0, 1]) for the active session.
  /// The repository also appends each emitted sample to
  /// [AudioCaptureSession.amplitudePeaks] so a finalize after subscription
  /// loss still has data for the waveform.
  Stream<double> amplitudeStream(AudioCaptureSession session);

  /// Stops the recorder, builds the final 80-bucket waveform, applies the
  /// 10 MB cap (sets `truncated: true` if exceeded — no FFmpeg in v1; see
  /// progress-tracker open question 2), and returns a typed [AudioBlock].
  Future<AudioBlock> finalize(AudioCaptureSession session);

  /// Aborts the in-flight session: stops the recorder and removes the temp
  /// file. Must be safe to call from `Bloc.close()` (Invariant 8).
  Future<void> cancel(AudioCaptureSession session);

  /// Deletes a previously-finalized asset from disk. No-op if the file is
  /// already gone.
  Future<void> delete({required String noteId, required String audioId});

  /// Resolves the on-disk file for an asset id. Used by playback widgets
  /// when a block carries only `(noteId, audioId)`. Note: the asset paths
  /// stored on `AudioBlock` are absolute, so this is mainly a convenience
  /// for migration / cleanup paths.
  Future<File> resolveFile({required String noteId, required String audioId});
}

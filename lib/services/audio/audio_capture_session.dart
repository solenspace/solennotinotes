/// In-flight handle for a single recording. Owned by [NoteEditorBloc] while
/// `state.isCapturingAudio` is true; finalized into an [AudioBlock] on stop
/// or discarded on cancel. The mutable [amplitudePeaks] buffer accumulates
/// dB-normalized samples (range [0, 1]) emitted by the recorder; the
/// repository down-samples it to a fixed-bucket waveform at finalize time.
class AudioCaptureSession {
  AudioCaptureSession({
    required this.id,
    required this.noteId,
    required this.tempFilePath,
    required this.startedAt,
  });

  final String id;
  final String noteId;
  final String tempFilePath;
  final DateTime startedAt;

  final List<double> amplitudePeaks = <double>[];
}

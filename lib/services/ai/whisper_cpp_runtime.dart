// Spec 21 (Whisper transcription) — once flutter-expert wires the chosen
// Whisper.cpp Dart binding (see "AWAITING flutter-expert validation"
// below), this file becomes the only file under lib/ permitted to import
// that package. The hygiene gate at that point is `scripts/.offline-allowlist`
// + `scripts/.forbidden-imports.txt` and the leading
// `// ignore_for_file: forbidden_import` directive (mirroring
// `llama_cpp_llm_runtime.dart`). Until then no forbidden import exists so
// no suppression is needed.

import 'dart:async';
import 'dart:isolate';

import 'whisper_runtime.dart';

/// Concrete [WhisperRuntime] that wraps the chosen Whisper.cpp Dart
/// binding (architecture decision #7 — `whisper_ggml` is the leading
/// candidate, mirroring the `llama_cpp_dart` choice for the LLM in
/// decision #32) behind a Dart `Isolate` so synchronous FFI calls cannot
/// stall the UI isolate. The runtime owns:
///
///   * one worker isolate (spawned on first [load], reused across
///     [transcribe] calls, killed by [unload]);
///   * a single bidirectional message protocol — the [_WhisperMsg]
///     hierarchy below — chosen so each message is a plain Dart object
///     and therefore copyable across the isolate boundary;
///   * a per-transcription [StreamController] keyed by an incrementing
///     id so two future overlapping transcriptions wouldn't share state.
///
/// Cancellation honours invariant 8: subscribing to the [transcribe]
/// stream and later calling `subscription.cancel()` posts a
/// [_StopCommand] to the worker, which the inner segment loop observes
/// between every Whisper segment (by yielding to the event loop after
/// each native call). The worker therefore aborts within a single
/// segment of the stop arriving, releasing the loop without disposing
/// the underlying model — a subsequent [transcribe] call reuses the
/// loaded context with no reload cost.
///
/// ## AWAITING flutter-expert validation
///
/// The single integration point with the native package is
/// [_runNativeWhisperTranscription] inside this file. Until
/// `flutter-expert` validates the Whisper.cpp Dart binding (per Spec 21
/// § Agents), that function emits a single `TranscriptionResult`
/// containing a placeholder string so the architecture is provably
/// shippable end-to-end (tests, UI, accept-paths) without a native
/// binding present. The cubit-level gate
/// (`WhisperReadinessCubit == ready` AND model file on disk) prevents
/// the placeholder from reaching users in production.
///
/// flutter-expert's validation pass must:
///
///   1. Pick the Whisper.cpp Dart binding (recommendation: `whisper_ggml`).
///   2. Add the package to `pubspec.yaml` (with the leading-comment block
///      mirroring `llama_cpp_dart`'s entry) and to
///      `scripts/.forbidden-imports.txt` as a hygiene gate confining the
///      import to this file.
///   3. Replace [_runNativeWhisperTranscription]'s body with the
///      package's load + transcribe calls. The function lives inside the
///      worker isolate, so FFI calls are safe.
///   4. Decide the m4a → 16 kHz mono PCM path: either the package
///      handles m4a directly, or a sibling decode step (platform channel
///      / `ffmpeg_kit_flutter_new`) lands as a follow-up. The audio block
///      `path` field always points at an `.m4a` file
///      (`<app_documents>/notes/<note_id>/audio/<audio_id>.m4a`).
///   5. Update the doc-comment above to remove this "awaiting" section
///      once the binding is wired.
class WhisperCppRuntime implements WhisperRuntime {
  WhisperCppRuntime();

  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  StreamSubscription<dynamic>? _portSub;

  bool _isLoaded = false;
  int _nextTranscriptionId = 1;
  final Map<int, StreamController<TranscriptionEvent>> _activeTranscriptions = {};

  Completer<SendPort>? _handshakeCompleter;
  Completer<bool>? _loadCompleter;
  Completer<void>? _unloadCompleter;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<bool> load({required String modelPath}) async {
    if (_isolate != null) await unload();

    _fromIsolate = ReceivePort();
    _portSub = _fromIsolate!.listen(_onIsolateMessage);
    _handshakeCompleter = Completer<SendPort>();

    _isolate = await Isolate.spawn<SendPort>(
      _isolateEntry,
      _fromIsolate!.sendPort,
      errorsAreFatal: true,
      debugName: 'WhisperCppRuntime',
    );

    _toIsolate = await _handshakeCompleter!.future;

    _loadCompleter = Completer<bool>();
    _toIsolate!.send(_LoadCommand(modelPath: modelPath));
    final ok = await _loadCompleter!.future;
    _isLoaded = ok;
    if (!ok) {
      // Clean up the worker on a failed load so the next [load] starts cold.
      await unload();
    }
    return ok;
  }

  @override
  Stream<TranscriptionEvent> transcribe({required String audioFilePath}) {
    if (!_isLoaded || _toIsolate == null) {
      return Stream<TranscriptionEvent>.error(
        StateError(
          'WhisperRuntime: transcribe() called before a successful load().',
        ),
      );
    }

    final id = _nextTranscriptionId++;
    late final StreamController<TranscriptionEvent> controller;
    controller = StreamController<TranscriptionEvent>(
      onCancel: () {
        // Tell the worker to stop; let _onIsolateMessage close the
        // controller when the worker acknowledges with _TranscribeDone.
        // Avoids a race where a segment in flight would be added to a
        // closed controller.
        _toIsolate?.send(_StopCommand(id: id));
      },
    );
    _activeTranscriptions[id] = controller;
    _toIsolate!.send(
      _TranscribeCommand(id: id, audioFilePath: audioFilePath),
    );
    return controller.stream;
  }

  @override
  Future<void> unload() async {
    if (_isolate == null) {
      _isLoaded = false;
      return;
    }

    // Close any in-flight subscribers — the worker will be torn down.
    for (final controller in _activeTranscriptions.values) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
    _activeTranscriptions.clear();

    if (_toIsolate != null) {
      _unloadCompleter = Completer<void>();
      _toIsolate!.send(const _UnloadCommand());
      try {
        await _unloadCompleter!.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Worker did not ack — fall through to forced kill below.
      }
    }

    _isolate!.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    await _portSub?.cancel();
    _portSub = null;
    _fromIsolate?.close();
    _fromIsolate = null;
    _handshakeCompleter = null;
    _loadCompleter = null;
    _unloadCompleter = null;
    _isLoaded = false;
  }

  void _onIsolateMessage(dynamic msg) {
    if (msg is SendPort) {
      _handshakeCompleter?.complete(msg);
      _handshakeCompleter = null;
      return;
    }
    if (msg is! _WhisperMsg) return;
    switch (msg) {
      case _LoadResult(:final success):
        _loadCompleter?.complete(success);
        _loadCompleter = null;
      case _ProgressMsg(:final id, :final fraction):
        final c = _activeTranscriptions[id];
        if (c != null && !c.isClosed) c.add(TranscriptionProgress(fraction));
      case _ResultMsg(:final id, :final text):
        final c = _activeTranscriptions[id];
        if (c != null && !c.isClosed) c.add(TranscriptionResult(text));
      case _TranscribeDone(:final id):
        final c = _activeTranscriptions.remove(id);
        if (c != null && !c.isClosed) c.close();
      case _TranscribeError(:final id, :final message):
        final c = _activeTranscriptions.remove(id);
        if (c != null && !c.isClosed) {
          c.addError(StateError(message));
          c.close();
        }
      case _UnloadAck():
        _unloadCompleter?.complete();
        _unloadCompleter = null;
      // Inbound-only branches; the main isolate never receives commands.
      case _LoadCommand():
      case _TranscribeCommand():
      case _StopCommand():
      case _UnloadCommand():
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

/// Top-level isolate entry. Receives the parent's SendPort, opens its own
/// inbound port, sends the handshake reply, then dispatches commands.
///
/// The Whisper context lives in this isolate's local state; the parent
/// never touches the FFI binding directly. The transcription loop yields
/// to the event loop between every segment-progress emission so an
/// in-flight `_StopCommand` is processed within one segment of arrival —
/// the cancellation contract Spec 21 invariant 8 spells out.
Future<void> _isolateEntry(SendPort toMain) async {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  String? loadedModelPath;
  final stoppedIds = <int>{};

  await for (final msg in fromMain) {
    if (msg is! _WhisperMsg) continue;
    switch (msg) {
      case _LoadCommand(:final modelPath):
        try {
          // The native binding's `load` is invoked here once
          // flutter-expert wires it. Until then we simply remember the
          // path and report success — the placeholder transcription
          // path doesn't need a native context.
          loadedModelPath = modelPath;
          toMain.send(const _LoadResult(success: true));
        } catch (_) {
          loadedModelPath = null;
          toMain.send(const _LoadResult(success: false));
        }
      case _TranscribeCommand(:final id, :final audioFilePath):
        final modelPath = loadedModelPath;
        if (modelPath == null) {
          toMain.send(_TranscribeError(id: id, message: 'runtime not loaded'));
          continue;
        }
        try {
          await _runNativeWhisperTranscription(
            id: id,
            modelPath: modelPath,
            audioFilePath: audioFilePath,
            shouldAbort: () => stoppedIds.remove(id),
            sendProgress: (fraction) => toMain.send(_ProgressMsg(id: id, fraction: fraction)),
            sendResult: (text) => toMain.send(_ResultMsg(id: id, text: text)),
          );
        } catch (e) {
          toMain.send(_TranscribeError(id: id, message: e.toString()));
        }
        // Drop any late `_StopCommand` that arrived after the
        // transcription returned — without this the id stays in the
        // set forever (ids are monotonic, so never re-used; benign
        // unbounded leak otherwise). Mirrors the Llama runtime's
        // `if (!stopped) stoppedIds.remove(id)` discipline.
        stoppedIds.remove(id);
        // Always emit Done so the parent closes the controller; whether
        // the run finished naturally or was stopped is irrelevant from
        // the stream-lifecycle perspective.
        toMain.send(_TranscribeDone(id: id));
      case _StopCommand(:final id):
        stoppedIds.add(id);
      case _UnloadCommand():
        loadedModelPath = null;
        toMain.send(const _UnloadAck());
        fromMain.close();
        return;
      // Outbound-only branches; the worker never receives results.
      case _LoadResult():
      case _ProgressMsg():
      case _ResultMsg():
      case _TranscribeDone():
      case _TranscribeError():
      case _UnloadAck():
        break;
    }
  }
}

/// AWAITING flutter-expert validation — single integration point with
/// the chosen Whisper.cpp Dart binding.
///
/// **Current behaviour (placeholder):** emits one progress event then a
/// single result with a sentinel string. The architecture above (worker
/// isolate, message protocol, cancellation, per-transcription
/// `StreamController` routing) is fully exercised; only the FFI call
/// remains.
///
/// **Wiring contract for flutter-expert:**
///   * Initialise the Whisper context once per worker isolate against
///     [modelPath]. The context can be cached across calls.
///   * Decode [audioFilePath] (`.m4a`) to 16 kHz mono PCM if the chosen
///     binding does not accept m4a directly. Per architecture decision
///     #7 the canonical capture format remains m4a; transcoding lives
///     here, not at the recorder.
///   * Run inference. For every segment emitted by the native callback,
///     call [sendProgress] with the cumulative fraction processed
///     (`segmentEndMs / totalDurationMs`, clamped to [0,1]).
///   * Between segments, check [shouldAbort]. If true, return early
///     without calling [sendResult] — the cancellation path on the
///     parent isolate already closes the controller.
///   * Once the final segment arrives, call [sendResult] with the
///     trimmed transcript.
///   * Throw on unrecoverable native errors; the parent surfaces them
///     via the stream's error channel.
Future<void> _runNativeWhisperTranscription({
  required int id,
  required String modelPath,
  required String audioFilePath,
  required bool Function() shouldAbort,
  required void Function(double fraction) sendProgress,
  required void Function(String text) sendResult,
}) async {
  // Yield once so a `_StopCommand` already in the worker's queue is
  // observed before the placeholder runs to completion. Mirrors the
  // `Future.delayed(Duration.zero)` pattern in `LlamaCppLlmRuntime`'s
  // generation loop.
  await Future<void>.delayed(Duration.zero);
  if (shouldAbort()) return;

  sendProgress(0.0);
  await Future<void>.delayed(Duration.zero);
  if (shouldAbort()) return;

  sendProgress(1.0);
  sendResult(
    '[Transcription unavailable: native Whisper binding awaiting '
    'flutter-expert validation. See lib/services/ai/whisper_cpp_runtime.dart '
    'doc-comment for the wiring contract.]',
  );
}

// ---------------------------------------------------------------------------
// Message protocol — sealed so the switches above are exhaustive.
// ---------------------------------------------------------------------------

sealed class _WhisperMsg {
  const _WhisperMsg();
}

class _LoadCommand extends _WhisperMsg {
  const _LoadCommand({required this.modelPath});
  final String modelPath;
}

class _LoadResult extends _WhisperMsg {
  const _LoadResult({required this.success});
  final bool success;
}

class _TranscribeCommand extends _WhisperMsg {
  const _TranscribeCommand({required this.id, required this.audioFilePath});
  final int id;
  final String audioFilePath;
}

class _ProgressMsg extends _WhisperMsg {
  const _ProgressMsg({required this.id, required this.fraction});
  final int id;
  final double fraction;
}

class _ResultMsg extends _WhisperMsg {
  const _ResultMsg({required this.id, required this.text});
  final int id;
  final String text;
}

class _TranscribeDone extends _WhisperMsg {
  const _TranscribeDone({required this.id});
  final int id;
}

class _TranscribeError extends _WhisperMsg {
  const _TranscribeError({required this.id, required this.message});
  final int id;
  final String message;
}

class _StopCommand extends _WhisperMsg {
  const _StopCommand({required this.id});
  final int id;
}

class _UnloadCommand extends _WhisperMsg {
  const _UnloadCommand();
}

class _UnloadAck extends _WhisperMsg {
  const _UnloadAck();
}

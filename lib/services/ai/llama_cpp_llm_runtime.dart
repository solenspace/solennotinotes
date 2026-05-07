// ignore_for_file: forbidden_import
// Allowed by scripts/.offline-allowlist for Spec 20 (LLM runtime). This is
// the only file under lib/ permitted to import package:llama_cpp_dart — see
// architecture.md decision #32 and the allowlist comment for the audit
// trail. Adding a second consumer requires a written rationale and a new
// architecture-decision entry; do not silently extend.

import 'dart:async';
import 'dart:isolate';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import 'llm_runtime.dart';

/// Concrete [LlmRuntime] that wraps `llama_cpp_dart` (architecture
/// decision #32) behind a Dart `Isolate` so the synchronous `Llama.getNext`
/// call cannot stall the UI isolate. The runtime owns:
///
///   * one worker isolate (spawned on first [load], reused across
///     [generate] calls, killed by [unload]);
///   * a single bidirectional message protocol — the [_RuntimeMsg]
///     hierarchy below — chosen so each message is a plain Dart object
///     and therefore copyable across the isolate boundary without `Map`
///     stringly-typing;
///   * a per-generation [StreamController] keyed by an incrementing id,
///     so the worker's tokens are routed back to the correct subscriber
///     even if a future change ever overlaps generations.
///
/// Cancellation honours invariant 8: subscribing to the [generate]
/// stream and later calling `subscription.cancel()` posts a
/// [_StopCommand] to the worker, which the inner generation loop
/// observes between every token (by yielding to the event loop after
/// each `getNext`). The worker therefore aborts within a single token
/// of the stop arriving, releasing the loop without disposing the
/// underlying model — a subsequent [generate] call reuses the loaded
/// context with no reload cost.
class LlamaCppLlmRuntime implements LlmRuntime {
  LlamaCppLlmRuntime();

  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  StreamSubscription<dynamic>? _portSub;

  bool _isLoaded = false;
  int _nextGenerationId = 1;
  final Map<int, StreamController<String>> _activeGenerations = {};

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
      debugName: 'LlamaCppLlmRuntime',
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
  Stream<String> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
  }) {
    if (!_isLoaded || _toIsolate == null) {
      return Stream<String>.error(
        StateError('LlmRuntime: generate() called before a successful load().'),
      );
    }

    final id = _nextGenerationId++;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onCancel: () {
        // Tell the worker to stop sampling; let _onIsolateMessage close
        // the controller when the worker acknowledges with _GenerationDone.
        // This avoids a race where a token in flight would be added to a
        // closed controller.
        _toIsolate?.send(_StopCommand(id: id));
      },
    );
    _activeGenerations[id] = controller;
    _toIsolate!.send(
      _GenerateCommand(
        id: id,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
      ),
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
    for (final controller in _activeGenerations.values) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
    _activeGenerations.clear();

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
    if (msg is! _RuntimeMsg) return;
    switch (msg) {
      case _LoadResult(:final success):
        _loadCompleter?.complete(success);
        _loadCompleter = null;
      case _Token(:final id, :final text):
        final c = _activeGenerations[id];
        if (c != null && !c.isClosed) c.add(text);
      case _GenerationDone(:final id):
        final c = _activeGenerations.remove(id);
        if (c != null && !c.isClosed) c.close();
      case _GenerationError(:final id, :final message):
        final c = _activeGenerations.remove(id);
        if (c != null && !c.isClosed) {
          c.addError(StateError(message));
          c.close();
        }
      case _UnloadAck():
        _unloadCompleter?.complete();
        _unloadCompleter = null;
      // Inbound-only branches; the main isolate never receives commands.
      case _LoadCommand():
      case _GenerateCommand():
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
/// The Llama instance lives in this isolate's local state; the parent
/// never touches the FFI binding directly. Generation loops yield to the
/// event loop between every token (`Future.delayed(Duration.zero)`) so an
/// in-flight `_StopCommand` is processed within one token of arrival —
/// the cancellation contract Spec 18 invariant 8 spells out.
Future<void> _isolateEntry(SendPort toMain) async {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  Llama? llama;
  final stoppedIds = <int>{};

  await for (final msg in fromMain) {
    if (msg is! _RuntimeMsg) continue;
    switch (msg) {
      case _LoadCommand(:final modelPath):
        try {
          llama?.dispose();
          llama = Llama(modelPath);
          toMain.send(const _LoadResult(success: true));
        } catch (_) {
          llama = null;
          toMain.send(const _LoadResult(success: false));
        }
      case _GenerateCommand(:final id, :final prompt, :final maxTokens):
        final l = llama;
        if (l == null) {
          toMain.send(_GenerationError(id: id, message: 'runtime not loaded'));
          continue;
        }
        try {
          l.setPrompt(prompt);
        } catch (e) {
          toMain.send(_GenerationError(id: id, message: e.toString()));
          continue;
        }
        var emitted = 0;
        var stopped = false;
        while (emitted < maxTokens) {
          // Yield so an inbound _StopCommand for this id is processed
          // before the next sample. Without this, the synchronous
          // getNext loop would starve the port.
          await Future<void>.delayed(Duration.zero);
          if (stoppedIds.remove(id)) {
            stopped = true;
            break;
          }
          try {
            final next = l.getNext();
            final token = next.$1;
            final done = next.$2;
            toMain.send(_Token(id: id, text: token));
            emitted++;
            if (done) break;
          } catch (e) {
            toMain.send(_GenerationError(id: id, message: e.toString()));
            stopped = true;
            break;
          }
        }
        // Always emit Done so the parent closes the controller; whether
        // the run finished naturally, hit maxTokens, or was stopped is
        // irrelevant from the stream-lifecycle perspective.
        if (!stopped) stoppedIds.remove(id);
        toMain.send(_GenerationDone(id: id));
      case _StopCommand(:final id):
        stoppedIds.add(id);
      case _UnloadCommand():
        try {
          llama?.dispose();
        } catch (_) {
          // Native disposal best-effort; the isolate is about to die anyway.
        }
        llama = null;
        toMain.send(const _UnloadAck());
        fromMain.close();
        return;
      // Outbound-only branches; the worker never receives results.
      case _LoadResult():
      case _Token():
      case _GenerationDone():
      case _GenerationError():
      case _UnloadAck():
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Message protocol — sealed so the switches above are exhaustive.
// ---------------------------------------------------------------------------

sealed class _RuntimeMsg {
  const _RuntimeMsg();
}

class _LoadCommand extends _RuntimeMsg {
  const _LoadCommand({required this.modelPath});
  final String modelPath;
}

class _LoadResult extends _RuntimeMsg {
  const _LoadResult({required this.success});
  final bool success;
}

class _GenerateCommand extends _RuntimeMsg {
  const _GenerateCommand({
    required this.id,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
  });
  final int id;
  final String prompt;
  final int maxTokens;
  final double temperature;
}

class _Token extends _RuntimeMsg {
  const _Token({required this.id, required this.text});
  final int id;
  final String text;
}

class _GenerationDone extends _RuntimeMsg {
  const _GenerationDone({required this.id});
  final int id;
}

class _GenerationError extends _RuntimeMsg {
  const _GenerationError({required this.id, required this.message});
  final int id;
  final String message;
}

class _StopCommand extends _RuntimeMsg {
  const _StopCommand({required this.id});
  final int id;
}

class _UnloadCommand extends _RuntimeMsg {
  const _UnloadCommand();
}

class _UnloadAck extends _RuntimeMsg {
  const _UnloadAck();
}

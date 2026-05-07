// LLM runtime validation harness — Spec 18.
//
// Empirically scores a candidate llama.cpp binding against the seven
// pass/fail criteria in specs/18-llm-runtime-validation.md §"Validation
// criteria". Writes a JSON result file the implementer commits under
// results/, then transcribes into context/progress-tracker.md as
// architecture decision #32.
//
// This harness is NOT part of the Flutter app build. It runs as a pure Dart
// CLI on the desktop host (sanity-checks linkage / load latency / single-run
// generation) and as a swap-in inside a temporary Flutter shim app for
// physical-device runs. See ../README.md for both recipes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

// Candidate adapter imports live behind a top-level switch so an unpinned
// candidate's missing package doesn't break `dart pub get` for the others.
// To validate a candidate, uncomment its dependency in pubspec.yaml AND the
// matching import below, then flesh out the adapter's load/generate/unload
// against the binding's real API. The adapter shape mirrors the production
// `LlmRuntime` interface (lib/services/ai/llm_runtime.dart) so the winning
// adapter is a near-mechanical port for Spec 19.
//
// import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama_cpp_dart;
// import 'package:flutter_llama/flutter_llama.dart' as flutter_llama;

/// Fixed prompt for reproducibility across candidates and devices.
const String _benchmarkPrompt =
    'Write a one-paragraph note explaining why offline-first apps matter.';

/// Generation length per criterion: "Runs a 50-token generation".
const int _generationTokens = 50;

/// Sequential runs per criterion: "No crashes on 5 sequential generations".
const int _sequentialRuns = 5;

/// RSS-sampling cadence during generation; tracks max() to approximate peak.
const Duration _rssSamplePeriod = Duration(milliseconds: 50);

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'candidate',
      abbr: 'c',
      help: 'Candidate identifier (matches an adapter below).',
      allowed: const ['llama_cpp_dart', 'flutter_llama', 'mlc', 'custom_ffi'],
    )
    ..addOption('model', abbr: 'm', help: 'Absolute path to the GGUF model file.')
    ..addOption(
      'device-label',
      abbr: 'd',
      help: 'Stable identifier for this device (e.g. "iphone-15-pro-A17-full").',
    )
    ..addOption('output',
        abbr: 'o', help: 'Output JSON path. Defaults to results/<candidate>-<device>.json.')
    ..addMultiOption('notes',
        help: 'Free-form key=value pair captured into the result JSON. Use this to '
            'record manual criterion 1 metadata, e.g. --notes=flutter-sdk=3.41.4.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}\n');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (args['help'] as bool || argv.isEmpty) {
    stdout.writeln('Usage: dart run bin/probe.dart [options]\n');
    stdout.writeln(parser.usage);
    return;
  }

  final candidate = args['candidate'] as String?;
  final modelPath = args['model'] as String?;
  final deviceLabel = args['device-label'] as String?;
  if (candidate == null || modelPath == null || deviceLabel == null) {
    stderr.writeln('error: --candidate, --model, and --device-label are all required.\n');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final modelFile = File(modelPath);
  if (!modelFile.existsSync()) {
    stderr.writeln('error: model file not found: $modelPath');
    exitCode = 66;
    return;
  }

  final adapter = _adapterFor(candidate);
  if (adapter == null) {
    stderr.writeln(
      'error: candidate "$candidate" has no compiled-in adapter. Uncomment the '
      'matching import + dependency before running.',
    );
    exitCode = 70;
    return;
  }

  final outputPath =
      (args['output'] as String?) ?? p.join('results', '$candidate-$deviceLabel.json');
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);

  final notes = _parseNotes(args['notes'] as List<String>);

  final report = await _runProbe(
    adapter: adapter,
    candidate: candidate,
    modelPath: modelFile.absolute.path,
    deviceLabel: deviceLabel,
    notes: notes,
  );

  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );

  stdout.writeln('\n=== ${report.candidate} on ${report.deviceLabel} ===');
  for (final c in report.criteria) {
    stdout.writeln('  ${c.passed ? 'PASS' : 'FAIL'}  ${c.name}  (${c.detail})');
  }
  stdout.writeln('\nresults written to: ${outputFile.path}');
  exitCode = report.allPassed ? 0 : 1;
}

// ---------------------------------------------------------------------------
// Probe runner
// ---------------------------------------------------------------------------

Map<String, String> _parseNotes(List<String> raw) {
  final out = <String, String>{};
  for (final entry in raw) {
    final eq = entry.indexOf('=');
    if (eq <= 0) continue;
    out[entry.substring(0, eq)] = entry.substring(eq + 1);
  }
  return out;
}

Future<_Report> _runProbe({
  required _Adapter adapter,
  required String candidate,
  required String modelPath,
  required String deviceLabel,
  Map<String, String> notes = const {},
}) async {
  final criteria = <_Criterion>[];
  final modelSizeBytes = File(modelPath).lengthSync();
  final baselineRss = ProcessInfo.currentRss;

  // 1. Cold-load latency.
  final loadWatch = Stopwatch()..start();
  final loaded = await adapter.load(modelPath);
  loadWatch.stop();
  final loadMs = loadWatch.elapsedMilliseconds;
  criteria.add(_Criterion(
    name: 'load < 30s',
    passed: loaded && loadMs < 30000,
    detail: '${loadMs}ms; loaded=$loaded',
  ));

  if (!loaded) {
    return _Report(
      candidate: candidate,
      deviceLabel: deviceLabel,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      modelPath: modelPath,
      modelSizeBytes: modelSizeBytes,
      loadMs: loadMs,
      generations: const [],
      peakRssBytes: ProcessInfo.currentRss,
      criteria: criteria,
      notes: notes,
    );
  }

  // 2. Generation criteria — run the loop, sampling RSS in parallel.
  final generations = <_GenerationStats>[];
  var peakRss = baselineRss;
  var streamingObserved = false;
  var anyCrash = false;

  for (var i = 0; i < _sequentialRuns; i++) {
    final rssSampler = _RssSampler(period: _rssSamplePeriod, seed: peakRss);
    rssSampler.start();
    try {
      final stats = await _runOneGeneration(adapter, _benchmarkPrompt);
      generations.add(stats);
      if (stats.tokenCount > 1) streamingObserved = true;
    } on Object catch (e, st) {
      anyCrash = true;
      generations.add(_GenerationStats.crashed(error: '$e\n$st'));
    } finally {
      rssSampler.stop();
      if (rssSampler.peak > peakRss) peakRss = rssSampler.peak;
    }
  }

  await adapter.unload();

  // Aggregates.
  final firstGen = generations.first;
  final firstGenMs = firstGen.totalMs ?? -1;
  final tier = _expectedTier(deviceLabel);
  final genBudgetMs = tier == _Tier.full ? 30000 : 60000;

  criteria.add(_Criterion(
    name: '50-token gen budget',
    passed: firstGen.tokenCount >= _generationTokens && firstGenMs > 0 && firstGenMs < genBudgetMs,
    detail: '${firstGenMs}ms; tokens=${firstGen.tokenCount}; tier=$tier; budget=${genBudgetMs}ms',
  ));

  final memoryBudget = (modelSizeBytes * 1.5).round();
  final memoryDelta = peakRss - baselineRss;
  criteria.add(_Criterion(
    name: 'peak memory delta < 1.5x model',
    passed: memoryDelta > 0 && memoryDelta < memoryBudget,
    detail:
        'delta=${_mb(memoryDelta)}MB; model=${_mb(modelSizeBytes)}MB; budget=${_mb(memoryBudget)}MB',
  ));

  criteria.add(_Criterion(
    name: 'no crashes on 5 sequential gens',
    passed: !anyCrash && generations.length == _sequentialRuns,
    detail: 'runs=${generations.length}; crashed=$anyCrash',
  ));

  criteria.add(_Criterion(
    name: 'streaming token callback observed',
    passed: streamingObserved,
    detail: 'tokens-per-event from first run: ${firstGen.tokenCount}',
  ));

  return _Report(
    candidate: candidate,
    deviceLabel: deviceLabel,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    modelPath: modelPath,
    modelSizeBytes: modelSizeBytes,
    loadMs: loadMs,
    generations: generations,
    peakRssBytes: peakRss,
    criteria: criteria,
    notes: notes,
  );
}

Future<_GenerationStats> _runOneGeneration(_Adapter adapter, String prompt) async {
  final watch = Stopwatch()..start();
  final tokens = <String>[];
  final perTokenMs = <int>[];
  var lastTickMs = 0;
  await for (final chunk in adapter.generate(prompt: prompt, maxTokens: _generationTokens)) {
    tokens.add(chunk);
    perTokenMs.add(watch.elapsedMilliseconds - lastTickMs);
    lastTickMs = watch.elapsedMilliseconds;
  }
  watch.stop();
  return _GenerationStats(
    tokenCount: tokens.length,
    totalMs: watch.elapsedMilliseconds,
    perTokenMs: perTokenMs,
  );
}

int _mb(int bytes) => (bytes / (1024 * 1024)).round();

enum _Tier { full, compact, unknown }

_Tier _expectedTier(String deviceLabel) {
  final lower = deviceLabel.toLowerCase();
  if (lower.contains('-full')) return _Tier.full;
  if (lower.contains('-compact')) return _Tier.compact;
  return _Tier.unknown;
}

// ---------------------------------------------------------------------------
// RSS sampler — `ProcessInfo.currentRss` is point-in-time, so we poll and
// keep the max. Approximate but reproducible across candidates.
// ---------------------------------------------------------------------------

class _RssSampler {
  _RssSampler({required this.period, required int seed}) : peak = seed;
  final Duration period;
  int peak;
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(period, (_) {
      final now = ProcessInfo.currentRss;
      if (now > peak) peak = now;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

// ---------------------------------------------------------------------------
// Adapters — one per candidate. The probe imports the binding directly so a
// missing native library shows up as a build error, not a runtime surprise.
// Each adapter wraps the binding behind the same shape as the production
// `LlmRuntime` interface (lib/services/ai/llm_runtime.dart) so Spec 19's
// concrete implementation is a near-mechanical port of the winning adapter.
// ---------------------------------------------------------------------------

abstract class _Adapter {
  Future<bool> load(String modelPath);
  Stream<String> generate({required String prompt, required int maxTokens});
  Future<void> unload();
}

_Adapter? _adapterFor(String candidate) {
  switch (candidate) {
    case 'llama_cpp_dart':
      return _LlamaCppDartAdapter();
    case 'flutter_llama':
      // return _FlutterLlamaAdapter();
      return null;
    case 'mlc':
    case 'custom_ffi':
      return null;
  }
  return null;
}

/// Adapter for `llama_cpp_dart` — the lead candidate per architecture
/// decision #6. The skeleton is intentionally unimplemented: pinning the
/// binding's real API to a versioned snapshot is part of Spec 18's work.
/// To wire it up:
///
///   1. Uncomment `llama_cpp_dart` in pubspec.yaml and the matching import
///      at the top of this file; run `dart pub get`.
///   2. Replace each `throw UnimplementedError(...)` below with a call into
///      the binding (load → constructor / `init`; generate → token stream;
///      unload → `dispose` / equivalent).
///   3. Re-run `dart analyze`; then `dart run bin/probe.dart --candidate=
///      llama_cpp_dart --model=<gguf> --device-label=<id>`.
///
/// The adapter shape itself is locked to mirror `LlmRuntime`, so once the
/// real calls land here Spec 19's port is mechanical.
class _LlamaCppDartAdapter implements _Adapter {
  @override
  Future<bool> load(String modelPath) async {
    throw UnimplementedError(
      'Wire llama_cpp_dart.load(modelPath) — see README §"Running on macOS desktop".',
    );
  }

  @override
  Stream<String> generate({required String prompt, required int maxTokens}) {
    throw UnimplementedError(
      'Wire the binding\'s per-token stream into this method.',
    );
  }

  @override
  Future<void> unload() async {
    throw UnimplementedError('Wire the binding\'s dispose / unload here.');
  }
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class _Report {
  _Report({
    required this.candidate,
    required this.deviceLabel,
    required this.timestamp,
    required this.modelPath,
    required this.modelSizeBytes,
    required this.loadMs,
    required this.generations,
    required this.peakRssBytes,
    required this.criteria,
    required this.notes,
  });

  final String candidate;
  final String deviceLabel;
  final String timestamp;
  final String modelPath;
  final int modelSizeBytes;
  final int loadMs;
  final List<_GenerationStats> generations;
  final int peakRssBytes;
  final List<_Criterion> criteria;
  final Map<String, String> notes;

  bool get allPassed => criteria.every((c) => c.passed);

  Map<String, Object?> toJson() => {
        'candidate': candidate,
        'deviceLabel': deviceLabel,
        'timestamp': timestamp,
        'model': {'path': modelPath, 'sizeBytes': modelSizeBytes},
        'loadMs': loadMs,
        'peakRssBytes': peakRssBytes,
        'generations': generations.map((g) => g.toJson()).toList(),
        'criteria': criteria.map((c) => c.toJson()).toList(),
        'allPassed': allPassed,
        'notes': notes,
      };
}

class _GenerationStats {
  _GenerationStats({
    required this.tokenCount,
    required this.totalMs,
    required this.perTokenMs,
    this.error,
  });

  factory _GenerationStats.crashed({required String error}) => _GenerationStats(
        tokenCount: 0,
        totalMs: null,
        perTokenMs: const [],
        error: error,
      );

  final int tokenCount;
  final int? totalMs;
  final List<int> perTokenMs;
  final String? error;

  Map<String, Object?> toJson() => {
        'tokenCount': tokenCount,
        'totalMs': totalMs,
        'perTokenMs': perTokenMs,
        if (error != null) 'error': error,
      };
}

class _Criterion {
  _Criterion({required this.name, required this.passed, required this.detail});

  final String name;
  final bool passed;
  final String detail;

  Map<String, Object?> toJson() => {
        'name': name,
        'passed': passed,
        'detail': detail,
      };
}

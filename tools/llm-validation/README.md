# LLM runtime validation harness — Spec 18

Empirical pass/fail probe for the candidate llama.cpp Flutter/Dart bindings.
Run it once per candidate per device tier; commit the resulting JSON under
`results/`; transcribe the winner into
[`context/progress-tracker.md`](../../context/progress-tracker.md) as
architecture decision #32.

This project is **not** part of the Flutter app build. It has its own
`pubspec.yaml` and lives outside `lib/` so the offline-imports gate
(`scripts/check-offline.sh`) does not scan it. Adding a candidate package
here does not affect the main app.

## Pre-requisites

- Dart SDK ≥ 3.4.0 (the harness is pure Dart on the desktop side).
- A GGUF model file. Spec 18 §"Validation criteria" pins this:
  **TinyLlama-1.1B-Chat Q4_K_M (~700 MB)**. Download from a trusted GGUF host
  (e.g. [TheBloke on Hugging Face](https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF))
  and verify the SHA-256 against the model card.
- For physical-device runs: a Flutter shim app (recipe below).

## Running on macOS desktop (sanity check)

This is the fast path: confirms the candidate's package resolves, the
shared library links, and a 50-token generation completes. It does **not**
satisfy Spec 18's `AiTier.full` / `AiTier.compact` criteria — those require
real iOS/Android hardware.

```bash
cd tools/llm-validation
dart pub get

# Drop the OS page cache so load-latency is genuinely cold. Without this
# step a re-run with the GGUF still resident in unified memory will
# under-report the load time by an order of magnitude — exactly the
# false-positive criterion 2 is meant to prevent.
sudo purge

dart run bin/probe.dart \
  --candidate=llama_cpp_dart \
  --model=/absolute/path/to/tinyllama-1.1b-chat-q4_k_m.gguf \
  --device-label=macos-host \
  --notes=flutter-sdk=3.41.4
```

Result lands at `results/llama_cpp_dart-macos-host.json` with one entry per
criterion. Exit code `0` on full pass, `1` on any fail. Re-run `sudo purge`
between every probe invocation; on iOS / Android, force-quit (not just
background) the shim app between runs so the OS reclaims the model pages.

## Running on iOS / Android

Pure-Dart `dart run` cannot target a phone. To benchmark on device:

1. Create a temporary Flutter app under `tools/llm-validation/shim/` (do
   **not** add it to the main `pubspec.yaml`):
   ```bash
   cd tools/llm-validation
   flutter create --template=app --platforms=ios,android shim
   ```
2. **Android: pin the ABI.** Every candidate ships prebuilt `.so` files
   that target `arm64-v8a`. Edit `shim/android/app/build.gradle` and add
   `ndk { abiFilters 'arm64-v8a' }` inside `android { defaultConfig { ... } }`.
   Without this step the shim builds for every ABI and silently fails to
   load the binding on a 32-bit device, masking the criterion-1 result.
3. **iOS: set a Development Team.** Open
   `shim/ios/Runner.xcworkspace`, select the `Runner` target → Signing &
   Capabilities, pick a team. Without this `flutter run` against a
   physical iPhone fails at codesign with a message that does not name
   the missing model.
4. Copy `bin/probe.dart`'s `_runProbe` and adapter classes into
   `shim/lib/main.dart`, replacing the `dart:io` exit-code surfacing with a
   single in-app screen that runs the probe on a button press and writes
   the JSON to the app's documents directory.
5. Add the candidate package to `shim/pubspec.yaml` (mirroring the active
   block in `tools/llm-validation/pubspec.yaml`).
6. Build the shim, install it on the test device, run the probe, transfer
   the JSON back to `tools/llm-validation/results/`.
7. Delete `tools/llm-validation/shim/` once results are committed — it is
   throwaway scaffolding, not a kept artefact.

The shim app exists only so the candidate's binding can load on the target
OS. The probe logic itself stays in `bin/probe.dart` as the authoritative
source.

## Validating MLC

MLC LLM has no published Dart package. To benchmark candidate #3:

1. Build `mlc-llm` for the target platform per the upstream README.
2. Vendor the resulting `libmlc_llm.dylib` (macOS) / `libmlc_llm.so`
   (Android) under `tools/llm-validation/native/`.
3. Add a `_MlcAdapter` in `bin/probe.dart` that opens the library via
   `dart:ffi` and bridges `load` / `generate` / `unload`.
4. Wire the adapter into `_adapterFor()` and run with `--candidate=mlc`.

## Validating custom FFI

Last-resort path. Same recipe as MLC but against a `libllama.dylib` /
`libllama.so` you build yourself from a known llama.cpp commit. Document
the commit SHA in the result JSON's `notes` field.

## The seven validation criteria

Sourced from [`specs/18-llm-runtime-validation.md`](../../specs/18-llm-runtime-validation.md)
§"Validation criteria". The probe scores criteria 2–6 mechanically; 1 and 7
are checked by the implementer:

1. **Builds cleanly on iOS + Android** — manual; verified during the shim
   build step above. Record the host Flutter SDK version in the result
   JSON's `notes` field.
2. Loads a 1B-Q4 GGUF in < 30s.
3. 50-token gen in < 30s on `AiTier.full`, < 60s on `AiTier.compact`.
4. Peak memory delta < 1.5× model size during generation.
   *Note on iOS measurement:* the harness samples
   `ProcessInfo.currentRss` every 50 ms and tracks the max. On iOS this
   maps to `proc_pidinfo(PROC_PIDTASKINFO).pti_resident_size`, which can
   under-report the true high-water mark by ~10–20% under memory pressure
   compared to `phys_footprint` (what Xcode Instruments shows). If the
   probe passes criterion 4 on iOS, eyeball one shim run in Xcode →
   Instruments → Allocations to confirm `phys_footprint` stays inside
   budget — the only manual step on this otherwise mechanical criterion.
5. No crashes on 5 sequential generations with the same model loaded.
6. Streaming token callback fires per token (essential for the Spec 20
   editor UX).
7. **No transitive network imports** — manual; from the repo root run
   `bash scripts/check-offline.sh` after temporarily adding the candidate
   to the main `pubspec.yaml`. Revert the addition; the gate's clean exit
   confirms the candidate is offline-safe. Spec 19 lands the actual
   addition.

A candidate "passes" only when all seven hold on at least one
`AiTier.full` device and one `AiTier.compact` device.

## Recording the decision

Once a candidate passes on both tiers:

1. Commit the per-tier JSONs to `results/`.
2. Append architecture decision #32 to
   [`context/progress-tracker.md`](../../context/progress-tracker.md)
   using the template from
   [`specs/18-llm-runtime-validation.md`](../../specs/18-llm-runtime-validation.md)
   §"Decision encoding". Concrete numbers — load latency, 50-token wall
   clock, peak memory delta, device names — go in the body. (The spec
   text suggests #24/#25 but those, and every integer through #31, are
   already taken by prior specs; #32 is the next free slot.)
3. Move the active-spec pointer in `progress-tracker.md` to
   `19-llm-model-download` and supersede architecture decision #6 with a
   reference to #31.

If **none** of the four candidates pass, follow Spec 18 §"Fallback path":
record decision #32-fallback and defer Specs 19–21 to v2.

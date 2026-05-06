import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';

/// Contract for the user-chrome settings store. Concrete implementations
/// may target Hive (current), in-memory (tests), or a future on-device
/// store.
abstract class SettingsRepository {
  /// Initialize backing storage. Idempotent; multiple calls are safe.
  ///
  /// When [identityRepository] is supplied, `init` performs a one-shot
  /// migration of the legacy Spec-9 `appThemeColor` Hive key into
  /// `NotiIdentity.signaturePalette[2]`, then deletes the legacy key.
  /// Tests that don't care about the migration may pass `null`.
  Future<void> init({NotiIdentityRepository? identityRepository});

  /// Returns the current settings. Implementations guarantee a record
  /// exists after [init], so this never returns null.
  Future<Settings> getCurrent();

  /// Emits the current settings on subscription, then on every save.
  /// Caller is responsible for cancelling the subscription.
  Stream<Settings> watch();

  /// Persists the settings. Overwrites any existing record.
  Future<void> save(Settings settings);

  /// Whether the device passed the cold-start STT capability probe (Spec 15).
  /// Cached separately from [Settings] because it is a device-capability fact,
  /// not a user-chrome preference; defaults to `false` so the dictation UI
  /// hides itself when the probe has not run yet.
  Future<bool> getSttOfflineCapable();

  Future<void> setSttOfflineCapable(bool value);

  /// Preferred TTS voice name (Spec 16). `null` = use the OS default voice.
  /// The voice is resolved against [TtsService.availableVoices] at speak
  /// time; an unknown name silently falls back to the OS default.
  ///
  /// Stored as separate KV pairs (mirroring [getSttOfflineCapable]) rather
  /// than folded into [Settings] so theme/font writes do not rewrite TTS
  /// keys. The future settings-overhaul spec surfaces these in the UI.
  Future<String?> getTtsVoice();

  Future<void> setTtsVoice(String? value);

  /// TTS speech rate. Plugin bounds are roughly `[0.1, 2.0]`; the wrapper
  /// clamps. Defaults to `1.0` (engine native rate).
  Future<double> getTtsRate();

  Future<void> setTtsRate(double value);

  /// TTS pitch. Plugin bounds are `[0.5, 2.0]`; the wrapper clamps.
  /// Defaults to `1.0` (engine native pitch).
  Future<double> getTtsPitch();

  Future<void> setTtsPitch(double value);

  /// Cached device-capability tier (Spec 17). Stored as the lower-cased
  /// [AiTier] enum name. `null` means the cold-start probe has not yet
  /// run; consumers should treat that as `AiTier.unsupported` (the
  /// hide-AI default).
  ///
  /// Stored as separate KV pairs (mirroring [getSttOfflineCapable]) rather
  /// than folded into [Settings] because the cache is a device-capability
  /// fact, not a user-chrome preference; bundling it would mean every
  /// theme/font save also rewrites the seven cap keys.
  Future<String?> getAiTier();

  Future<void> setAiTier(String? value);

  /// Total physical RAM in bytes from the most recent probe. `null` =
  /// never probed; `0` = probed but the platform did not report a value
  /// (Android OEM corner case — the classifier treats this as "unknown").
  Future<int?> getRamBytes();

  Future<void> setRamBytes(int? value);

  /// iOS major version (e.g. `17`) on iOS, Android API level (e.g. `33`)
  /// on Android. `null` = never probed.
  Future<int?> getOsMajorVersion();

  Future<void> setOsMajorVersion(int? value);

  /// Whether the device CPU supports arm64. `null` = never probed.
  Future<bool?> getArchIsArm64();

  Future<void> setArchIsArm64(bool? value);

  /// iOS-only Metal support flag from the most recent probe. Always
  /// `false` on Android. `null` = never probed.
  Future<bool?> getHasMetal();

  Future<void> setHasMetal(bool? value);

  /// iOS-only Apple Neural Engine flag (A12+). Always `false` on Android.
  /// `null` = never probed.
  Future<bool?> getHasNeuralEngine();

  Future<void> setHasNeuralEngine(bool? value);

  /// `Platform.operatingSystemVersion` from the most recent probe. The
  /// probe re-runs whenever the live value differs, so an OS upgrade
  /// after the cold-start probe is honoured before any AI feature load.
  Future<String?> getLastProbedOsVersion();

  Future<void> setLastProbedOsVersion(String? value);
}

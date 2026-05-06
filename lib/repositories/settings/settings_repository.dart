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
}

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
}

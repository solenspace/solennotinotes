/// Outcome of a permission request or status check. Mirrors the underlying
/// plugin's status enum but lives in our own namespace so plugin churn does
/// not ripple through the codebase.
enum PermissionResult {
  /// User granted the permission.
  granted,

  /// User denied this time but may re-prompt on a later request.
  denied,

  /// User selected "Don't ask again" / disabled in Settings. The OS will
  /// not prompt again until the user toggles it on in Settings.
  permanentlyDenied,

  /// Restricted by parental controls or device policy. Not user-toggleable.
  restricted,

  /// iOS 14+ photos: user granted access to a curated subset only. The
  /// app should treat this like granted but with a smaller set of assets.
  limited;

  bool get isUsable => this == granted || this == limited;

  bool get isFinalDenial => this == permanentlyDenied || this == restricted;
}

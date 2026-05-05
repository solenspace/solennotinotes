import 'dart:io';
import 'dart:ui';

import 'package:uuid/uuid.dart';

/// A user's signature identity. Travels with every shared note so the
/// receiver renders the sender's preferred look (palette, pattern, accent,
/// tagline) faithfully.
class NotiIdentity {
  NotiIdentity({
    required this.id,
    required this.displayName,
    required this.bornDate,
    required this.signaturePalette,
    this.profilePicture,
    this.signaturePatternKey,
    this.signatureAccent,
    this.signatureTagline = '',
  });

  /// Stable per-install UUID. Never changes after first generation.
  final String id;

  String displayName;
  DateTime bornDate;
  File? profilePicture;

  /// Swatches the user picked as "their" colors. Receivers render shared
  /// notes' default backgrounds against this palette. Must be non-empty.
  List<Color> signaturePalette;

  /// Key into the bundled pattern set (see [NotiPatternKey]). Null = none.
  String? signaturePatternKey;

  /// Exactly 0 or 1 user-perceived character. Rendered as a small badge
  /// on the user's noti chip and on shared notes.
  String? signatureAccent;

  /// A short user-authored line (≤ 60 chars). Shown on the share-preview
  /// card the receiver sees before accepting a note.
  String signatureTagline;

  /// Returns a fresh [NotiIdentity] with the given fields overridden. Pass
  /// `clearProfilePicture: true` (or `clearSignaturePatternKey: true` /
  /// `clearSignatureAccent: true`) to set a nullable field back to null —
  /// the named overrides cannot distinguish "not provided" from "null".
  NotiIdentity copyWith({
    String? displayName,
    DateTime? bornDate,
    File? profilePicture,
    List<Color>? signaturePalette,
    String? signaturePatternKey,
    String? signatureAccent,
    String? signatureTagline,
    bool clearProfilePicture = false,
    bool clearSignaturePatternKey = false,
    bool clearSignatureAccent = false,
  }) {
    return NotiIdentity(
      id: id,
      displayName: displayName ?? this.displayName,
      bornDate: bornDate ?? this.bornDate,
      profilePicture: clearProfilePicture ? null : (profilePicture ?? this.profilePicture),
      signaturePalette: signaturePalette ?? this.signaturePalette,
      signaturePatternKey:
          clearSignaturePatternKey ? null : (signaturePatternKey ?? this.signaturePatternKey),
      signatureAccent: clearSignatureAccent ? null : (signatureAccent ?? this.signatureAccent),
      signatureTagline: signatureTagline ?? this.signatureTagline,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'bornDate': bornDate.toIso8601String(),
        'profilePicture': profilePicture?.path,
        'signaturePalette': signaturePalette.map((c) => c.toARGB32()).toList(growable: false),
        'signaturePatternKey': signaturePatternKey,
        'signatureAccent': signatureAccent,
        'signatureTagline': signatureTagline,
      };

  factory NotiIdentity.fromJson(Map<String, dynamic> json) {
    return NotiIdentity(
      id: json['id'] as String,
      displayName: (json['displayName'] ?? json['name'] ?? '') as String,
      bornDate: DateTime.parse(json['bornDate'] as String),
      profilePicture:
          json['profilePicture'] != null ? File(json['profilePicture'] as String) : null,
      signaturePalette: (json['signaturePalette'] as List?)?.cast<int>().map(Color.new).toList() ??
          List.of(NotiIdentityDefaults.starterPalettes.first),
      signaturePatternKey: json['signaturePatternKey'] as String?,
      signatureAccent: json['signatureAccent'] as String?,
      signatureTagline: (json['signatureTagline'] as String?) ?? '',
    );
  }

  /// Generates a fresh identity with a randomly-picked starter palette.
  factory NotiIdentity.fresh({String displayName = ''}) {
    final palettes = NotiIdentityDefaults.starterPalettes;
    return NotiIdentity(
      id: const Uuid().v4(),
      displayName: displayName,
      bornDate: DateTime.now(),
      signaturePalette: List.of(
        palettes[DateTime.now().microsecond % palettes.length],
      ),
    );
  }
}

class NotiIdentityDefaults {
  /// Starter palettes — each entry is an ordered list of swatches
  /// (background, surface, accent, text-on-accent). Picked at random
  /// for first-launch identities so two users get different defaults.
  static const List<List<Color>> starterPalettes = [
    [Color(0xFF2D2D2D), Color(0xFF383838), Color(0xFFE5B26B), Color(0xFFF2EFEA)],
    [Color(0xFF1B1F2A), Color(0xFF24293A), Color(0xFF7BAFD4), Color(0xFFEAF1FA)],
    [Color(0xFF1F2620), Color(0xFF2A332C), Color(0xFF8FA66F), Color(0xFFEDF1E6)],
    [Color(0xFF2A1F26), Color(0xFF362A32), Color(0xFFD37FA0), Color(0xFFF7EDF1)],
  ];
}

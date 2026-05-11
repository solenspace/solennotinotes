import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// One pending entry in the received-shares inbox (Spec 25).
///
/// Wraps the verified [IncomingShare] data plus the local
/// [receivedAt] timestamp used for arrival-order display. Serializable
/// to a JSON string for Hive storage; the matching `received_inbox_v1`
/// box in [HiveReceivedInboxRepository] stores [shareId] → JSON.
///
/// Asset bytes themselves are not persisted here — they live on disk
/// under [inboxRoot] (`<documents>/inbox/<shareId>/`) where
/// [ShareDecoder] extracted them. Accept moves them into the note
/// library; Discard rm -rf's the directory.
class ReceivedShare extends Equatable {
  const ReceivedShare({
    required this.shareId,
    required this.receivedAt,
    required this.sender,
    required this.note,
    required this.assets,
    required this.inboxRoot,
  });

  final String shareId;
  final DateTime receivedAt;
  final IncomingSender sender;
  final IncomingNote note;
  final List<IncomingAsset> assets;
  final String inboxRoot;

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'share_id': shareId,
      'received_at': receivedAt.toIso8601String(),
      'inbox_root': inboxRoot,
      'sender': _senderToJson(sender),
      'note': _noteToJson(note),
      'assets': assets.map(_assetToJson).toList(growable: false),
    };
  }

  factory ReceivedShare.fromJsonString(String source) =>
      ReceivedShare.fromJson(jsonDecode(source) as Map<String, dynamic>);

  factory ReceivedShare.fromJson(Map<String, dynamic> json) {
    return ReceivedShare(
      shareId: json['share_id'] as String,
      receivedAt: DateTime.parse(json['received_at'] as String),
      inboxRoot: json['inbox_root'] as String,
      sender: _senderFromJson(json['sender'] as Map<String, dynamic>),
      note: _noteFromJson(json['note'] as Map<String, dynamic>),
      assets: (json['assets'] as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => _assetFromJson(m.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  /// Sender's chip color resolved from the verified manifest. Prefers
  /// `signaturePalette[2]` (the App Style accent slot, per the spec's
  /// note-card swatch convention) and falls back to the note overlay's
  /// accent so a sparsely-populated palette never crashes the inbox UI.
  Color get senderAccentColor {
    final palette = sender.signaturePalette;
    if (palette.isEmpty) return note.overlay.accent;
    final i = palette.length > 2 ? 2 : palette.length - 1;
    return Color(palette[i]);
  }

  @override
  List<Object?> get props => [shareId, receivedAt, sender, note, assets, inboxRoot];
}

Map<String, dynamic> _senderToJson(IncomingSender s) => <String, dynamic>{
      'id': s.id,
      'display_name': s.displayName,
      'public_key': s.publicKey,
      'signature_palette': s.signaturePalette,
      'signature_pattern_key': s.signaturePatternKey,
      'signature_accent': s.signatureAccent,
      'signature_tagline': s.signatureTagline,
    };

IncomingSender _senderFromJson(Map<String, dynamic> json) => IncomingSender(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      publicKey: (json['public_key'] as List).cast<int>().toList(growable: false),
      signaturePalette: (json['signature_palette'] as List).cast<int>().toList(growable: false),
      signaturePatternKey: json['signature_pattern_key'] as String?,
      signatureAccent: json['signature_accent'] as String?,
      signatureTagline: (json['signature_tagline'] as String?) ?? '',
    );

Map<String, dynamic> _noteToJson(IncomingNote n) => <String, dynamic>{
      'id': n.id,
      'title': n.title,
      'blocks': n.blocks,
      'tags': n.tags,
      'date_created': n.dateCreated.toIso8601String(),
      'reminder': n.reminder?.toIso8601String(),
      'is_pinned': n.isPinned,
      'overlay': _overlayToJson(n.overlay),
    };

IncomingNote _noteFromJson(Map<String, dynamic> json) => IncomingNote(
      id: json['id'] as String,
      title: json['title'] as String,
      blocks: (json['blocks'] as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList(growable: false),
      tags: (json['tags'] as List).cast<String>().toList(growable: false),
      dateCreated: DateTime.parse(json['date_created'] as String),
      reminder: json['reminder'] is String ? DateTime.parse(json['reminder'] as String) : null,
      isPinned: json['is_pinned'] as bool,
      overlay: _overlayFromJson((json['overlay'] as Map).cast<String, dynamic>()),
    );

Map<String, dynamic> _overlayToJson(NotiThemeOverlay o) => <String, dynamic>{
      'surface': o.surface.toARGB32(),
      'surface_variant': o.surfaceVariant.toARGB32(),
      'accent': o.accent.toARGB32(),
      'on_accent': o.onAccent.toARGB32(),
      'on_surface': o.onSurface?.toARGB32(),
      'pattern_key': o.patternKey?.name,
      'signature_accent': o.signatureAccent,
      'signature_tagline': o.signatureTagline,
      'from_identity_id': o.fromIdentityId,
    };

NotiThemeOverlay _overlayFromJson(Map<String, dynamic> json) {
  Color color(Object? raw) => Color(raw! as int);
  Color? maybeColor(Object? raw) => raw == null ? null : Color(raw as int);
  return NotiThemeOverlay(
    surface: color(json['surface']),
    surfaceVariant: color(json['surface_variant']),
    accent: color(json['accent']),
    onAccent: color(json['on_accent']),
    onSurface: maybeColor(json['on_surface']),
    patternKey: NotiPatternKey.fromString(json['pattern_key'] as String?),
    signatureAccent: json['signature_accent'] as String?,
    signatureTagline: (json['signature_tagline'] as String?) ?? '',
    fromIdentityId: json['from_identity_id'] as String?,
  );
}

Map<String, dynamic> _assetToJson(IncomingAsset a) => <String, dynamic>{
      'id': a.id,
      'kind': a.kind.wireName,
      'path_in_archive': a.pathInArchive,
      'size_bytes': a.sizeBytes,
      'sha256': a.sha256,
    };

IncomingAsset _assetFromJson(Map<String, dynamic> json) => IncomingAsset(
      id: json['id'] as String,
      kind: ShareAssetKindWire.fromWire(json['kind'] as String?) ?? ShareAssetKind.image,
      pathInArchive: json['path_in_archive'] as String,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String,
    );

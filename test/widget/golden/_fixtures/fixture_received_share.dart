import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// A single inbox entry from a sender named "Alex" with the Bone palette,
/// a short title, two blocks (text + checklist), and a deterministic
/// `receivedAt`. Used by the inbox + preview-panel goldens.
ReceivedShare fixtureReceivedShareAlex({String shareId = 'sh-001'}) {
  return ReceivedShare(
    shareId: shareId,
    receivedAt: DateTime.utc(2026, 1, 5, 8),
    sender: const IncomingSender(
      id: 'alex',
      displayName: 'Alex',
      publicKey: <int>[0, 1, 2],
      signaturePalette: <int>[0xFFEDE6D6, 0xFFF5EFE2, 0xFF4A8A7F, 0xFF0F0F0F],
      signaturePatternKey: null,
      signatureAccent: '✦',
      signatureTagline: 'with care',
    ),
    note: IncomingNote(
      id: 'rcv-1',
      title: 'Dinner ideas',
      blocks: const <Map<String, dynamic>>[
        {'type': 'text', 'id': 't1', 'text': 'Pasta night Thursday — bring olives.'},
        {'type': 'checklist', 'id': 'c1', 'text': 'Confirm with Sam', 'checked': false},
        {'type': 'checklist', 'id': 'c2', 'text': 'Buy candles', 'checked': true},
      ],
      tags: const <String>[],
      dateCreated: DateTime.utc(2026, 1, 4, 19),
      reminder: null,
      isPinned: false,
      overlay: kCuratedPalettes[0].copyWith(
        signatureAccent: '✦',
        signatureTagline: 'with care',
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/golden-inbox/sh-001',
  );
}

ReceivedShare fixtureReceivedShareJamie() {
  return ReceivedShare(
    shareId: 'sh-002',
    receivedAt: DateTime.utc(2026, 1, 4, 17),
    sender: const IncomingSender(
      id: 'jamie',
      displayName: 'Jamie',
      publicKey: <int>[3, 4, 5],
      signaturePalette: <int>[0xFF1F2A35, 0xFF2A3744, 0xFF7BAFD4, 0xFF0E1822],
      signaturePatternKey: null,
      signatureAccent: '✶',
      signatureTagline: '',
    ),
    note: IncomingNote(
      id: 'rcv-2',
      title: 'Weekly retro',
      blocks: const <Map<String, dynamic>>[
        {'type': 'text', 'id': 't1', 'text': 'Top wins, top friction.'},
      ],
      tags: const <String>[],
      dateCreated: DateTime.utc(2026, 1, 4, 17),
      reminder: null,
      isPinned: false,
      overlay: NotiThemeOverlay(
        surface: kCuratedPalettes[8].surface,
        surfaceVariant: kCuratedPalettes[8].surfaceVariant,
        accent: kCuratedPalettes[8].accent,
        onAccent: kCuratedPalettes[8].onAccent,
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/golden-inbox/sh-002',
  );
}

ReceivedShare fixtureReceivedShareSam() {
  return ReceivedShare(
    shareId: 'sh-003',
    receivedAt: DateTime.utc(2026, 1, 3, 12),
    sender: const IncomingSender(
      id: 'sam',
      displayName: 'Sam',
      publicKey: <int>[6, 7, 8],
      signaturePalette: <int>[0xFF1F2620, 0xFF2A332C, 0xFF8FA66F, 0xFF111712],
      signaturePatternKey: null,
      signatureAccent: '✺',
      signatureTagline: '',
    ),
    note: IncomingNote(
      id: 'rcv-3',
      title: 'Trail map',
      blocks: const <Map<String, dynamic>>[
        {'type': 'text', 'id': 't1', 'text': 'Start at the north gate.'},
      ],
      tags: const <String>[],
      dateCreated: DateTime.utc(2026, 1, 3, 12),
      reminder: null,
      isPinned: false,
      overlay: NotiThemeOverlay(
        surface: kCuratedPalettes[9].surface,
        surfaceVariant: kCuratedPalettes[9].surfaceVariant,
        accent: kCuratedPalettes[9].accent,
        onAccent: kCuratedPalettes[9].onAccent,
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/golden-inbox/sh-003',
  );
}

List<ReceivedShare> fixtureReceivedShareTrio() => [
      fixtureReceivedShareAlex(),
      fixtureReceivedShareJamie(),
      fixtureReceivedShareSam(),
    ];

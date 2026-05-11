import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/share/cubit/share_nearby_state.dart';
import 'package:noti_notes_app/features/share/widgets/peer_card.dart';
import 'package:noti_notes_app/features/share/widgets/transfer_progress_panel.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

/// Spec 29 guard-rail: every share-sheet surface must carry semantic
/// affordances so screen-reader users can identify peers and follow
/// transfer progress.
Future<void> _pumpScaffold(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Share-sheet accessibility floor (Spec 29)', () {
    testWidgets('PeerCard exposes a Semantics label containing the peer display name',
        (tester) async {
      const peer = DiscoveredPeer(
        id: 'p1',
        displayName: 'Mateo',
        state: PeerConnectionState.found,
      );
      await _pumpScaffold(tester, PeerCard(peer: peer, onTap: () {}));

      // Find a Semantics widget whose label embeds the display name.
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      final hasNamedSemantics = semantics.any(
        (s) => (s.properties.label ?? '').contains('Mateo'),
      );
      expect(
        hasNamedSemantics,
        isTrue,
        reason: 'PeerCard must label itself with the peer display name (WCAG 4.1.2).',
      );
    });

    testWidgets('TransferProgressPanel wraps the live region around progress updates',
        (tester) async {
      const state = ShareNearbyState(
        phase: ShareNearbyPhase.sending,
        queue: <Note>[],
        queueIndex: 0,
        peers: [
          DiscoveredPeer(id: 'p1', displayName: 'Mateo', state: PeerConnectionState.connected),
        ],
        activePeerId: 'p1',
        fraction: 0.42,
      );
      await _pumpScaffold(
        tester,
        TransferProgressPanel(state: state, onCancel: () {}),
      );

      // At least one Semantics ancestor in the rendered tree must be a
      // live region — that is what announces "X percent" updates to
      // VoiceOver/TalkBack as the bytes flow (WCAG 4.1.3).
      final semanticsList = tester.widgetList<Semantics>(find.byType(Semantics));
      final liveRegionSemantics = semanticsList.where(
        (s) => s.properties.liveRegion == true,
      );
      expect(
        liveRegionSemantics,
        isNotEmpty,
        reason: 'TransferProgressPanel must wrap its progress label in '
            'Semantics(liveRegion: true) so screen readers announce updates (WCAG 4.1.3).',
      );

      // The live-region label must include the peer name and a numeric
      // percentage so updates are intelligible.
      final hasPeerLabel = liveRegionSemantics.any(
        (s) => (s.properties.label ?? '').contains('Mateo'),
      );
      expect(
        hasPeerLabel,
        isTrue,
        reason: 'TransferProgressPanel live region must address the peer by name.',
      );
      // 0.42 ⇒ "42 percent complete" — embeds the percent value so
      // VoiceOver/TalkBack announce the actual fraction, not just "sending".
      final hasPercent = liveRegionSemantics.any(
        (s) => (s.properties.label ?? '').contains('42'),
      );
      expect(
        hasPercent,
        isTrue,
        reason: 'TransferProgressPanel live region must include the percent value '
            'so each update conveys progress, not just activity (WCAG 4.1.3).',
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/share/cubit/share_nearby_state.dart';
import 'package:noti_notes_app/features/share/widgets/peer_card.dart';
import 'package:noti_notes_app/features/share/widgets/transfer_progress_panel.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

import '_fixtures/fixture_peers.dart';
import '_helpers/golden_text.dart';
import '_helpers/pump_scene.dart';

/// Three scenes covering the share-sheet body phases per Spec 27 § A:
/// `discover_empty`, `discover_with_peers`, `sending`. The sheet itself
/// stays base-themed (overlay propagation happens at the surrounding sheet
/// chrome, which only matters once the editor opens the picker — not here).
void main() {
  group('Share-sheet goldens', () {
    testWidgets('share_sheet — discover_empty', (tester) async {
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: const Scaffold(body: _DiscoverEmpty()),
      );
      await expectLater(
        find.byType(_DiscoverEmpty),
        matchesGoldenFile('../../goldens/share_sheet/discover_empty.png'),
      );
    });

    testWidgets('share_sheet — discover_with_peers', (tester) async {
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: const Scaffold(body: _DiscoverWithPeers()),
      );
      await expectLater(
        find.byType(_DiscoverWithPeers),
        matchesGoldenFile('../../goldens/share_sheet/discover_with_peers.png'),
      );
    });

    testWidgets('share_sheet — sending', (tester) async {
      const state = ShareNearbyState(
        phase: ShareNearbyPhase.sending,
        queue: [],
        queueIndex: 0,
        peers: [
          DiscoveredPeer(
            id: 'peer-1',
            displayName: 'Alex',
            state: PeerConnectionState.connected,
          ),
        ],
        fraction: 0.42,
        activePeerId: 'peer-1',
        activeTransferId: 'tx-1',
      );
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: Scaffold(
          body: SafeArea(
            child: TransferProgressPanel(state: state, onCancel: () {}),
          ),
        ),
      );
      await expectLater(
        find.byType(TransferProgressPanel),
        matchesGoldenFile('../../goldens/share_sheet/sending.png'),
      );
    });
  });
}

class _DiscoverWithPeers extends StatelessWidget {
  const _DiscoverWithPeers();

  @override
  Widget build(BuildContext context) {
    final peers = fixturePeers();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Send to a nearby device', style: Theme.of(context).textTheme.titleLarge),
            const Gap(16),
            for (final p in peers) ...[
              PeerCard(peer: p, onTap: () {}),
              const Gap(8),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscoverEmpty extends StatelessWidget {
  const _DiscoverEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching_rounded, size: 56, color: scheme.primary),
            const Gap(12),
            Text(
              'Looking for nearby people…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Gap(4),
            Text(
              'Make sure their Noti is open too.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

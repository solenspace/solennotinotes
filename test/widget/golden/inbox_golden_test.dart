import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/inbox/widgets/inbox_row.dart';
import 'package:noti_notes_app/features/inbox/widgets/share_preview_panel.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

import '_fixtures/fixture_received_share.dart';
import '_helpers/golden_text.dart';
import '_helpers/pump_scene.dart';

/// The inbox surface stays base-themed (the sender's overlay only takes
/// over inside the preview panel). Three scenes per Spec 27 § A:
/// `empty`, `three_entries`, `preview_panel`.
void main() {
  group('Inbox goldens', () {
    testWidgets('inbox — empty', (tester) async {
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: const Scaffold(
          body: _InboxEmptyBody(),
        ),
      );
      await expectLater(
        find.byType(_InboxEmptyBody),
        matchesGoldenFile('../../goldens/inbox/empty.png'),
      );
    });

    testWidgets('inbox — three_entries', (tester) async {
      final shares = fixtureReceivedShareTrio();
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: Scaffold(
          body: SafeArea(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: shares.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => InboxRow(share: shares[i], onTap: () {}),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(ListView),
        matchesGoldenFile('../../goldens/inbox/three_entries.png'),
      );
    });

    testWidgets('inbox — preview_panel', (tester) async {
      final share = fixtureReceivedShareAlex();
      await pumpScene(
        tester,
        theme: AppTheme.bone(text: goldenText()),
        child: SharePreviewPanel(
          share: share,
          onAccept: () {},
          onDiscard: () {},
        ),
      );
      await expectLater(
        find.byType(SharePreviewPanel),
        matchesGoldenFile('../../goldens/inbox/preview_panel.png'),
      );
    });
  });
}

class _InboxEmptyBody extends StatelessWidget {
  const _InboxEmptyBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: scheme.onSurfaceVariant),
            const Gap(12),
            Text(
              'No pending shares',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Gap(4),
            Text(
              'When someone sends you a note over Bluetooth it lands here.',
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

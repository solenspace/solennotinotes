import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/share/cubit/share_nearby_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens.dart';

class TransferProgressPanel extends StatelessWidget {
  const TransferProgressPanel({
    super.key,
    required this.state,
    required this.onCancel,
  });

  final ShareNearbyState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final peerName = _peerName(state) ?? 'peer';
    final percent = (state.fraction.clamp(0.0, 1.0) * 100).round();
    final queueSize = state.queue.length;
    final isMulti = queueSize > 1;
    final progressLine = isMulti
        ? context.l10n.share_sheet_sending_count(state.queueIndex + 1, queueSize, percent)
        : context.l10n.share_sheet_sending_percent(percent);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.share_sheet_sending_to(peerName),
            style: tokens.text.headlineMd.copyWith(color: colors.onSurface),
          ),
          Gap(tokens.spacing.md),
          ClipRRect(
            borderRadius: tokens.shape.pillRadius,
            child: LinearProgressIndicator(
              value: state.fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
          Gap(tokens.spacing.sm),
          Text(
            progressLine,
            style: tokens.text.labelMd.copyWith(color: colors.onSurfaceMuted),
          ),
          Gap(tokens.spacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onCancel,
              child: Text(
                context.l10n.common_cancel,
                style: TextStyle(color: colors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _peerName(ShareNearbyState state) {
    final id = state.activePeerId;
    if (id == null) return null;
    for (final peer in state.peers) {
      if (peer.id == id) return peer.displayName;
    }
    return null;
  }
}

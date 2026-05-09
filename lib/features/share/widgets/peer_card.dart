import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// A row in the discovery list. Renders the peer's display name with a
/// neutral chip avatar — the peer's signature palette is unknown until
/// the receive-side handshake (Spec 25) ships.
class PeerCard extends StatelessWidget {
  const PeerCard({super.key, required this.peer, required this.onTap});

  final DiscoveredPeer peer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final inFlight =
        peer.state == PeerConnectionState.inviting || peer.state == PeerConnectionState.accepting;
    final dimmed = peer.state == PeerConnectionState.disconnected;
    final tappable = onTap != null && !inFlight && !dimmed;

    return Semantics(
      label: 'Share with ${peer.displayName}',
      button: tappable,
      child: Material(
        color: colors.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.shape.md),
          side: BorderSide(color: colors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.shape.md),
          onTap: tappable ? onTap : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.md,
            ),
            child: Opacity(
              opacity: dimmed ? 0.55 : 1,
              child: Row(
                children: [
                  _Avatar(initials: _initialsOf(peer.displayName)),
                  Gap(tokens.spacing.md),
                  Expanded(
                    child: Text(
                      peer.displayName,
                      style: tokens.text.bodyLg.copyWith(color: colors.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (inFlight)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSurfaceMuted,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: tokens.text.labelMd.copyWith(color: colors.onSurface),
      ),
    );
  }
}

String _initialsOf(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Single row in the inbox list. Shows the sender's accent chip + display
/// name, the note's title (or first 40 chars of body), the sender's
/// tagline, and a relative arrival timestamp.
class InboxRow extends StatelessWidget {
  const InboxRow({
    super.key,
    required this.share,
    required this.onTap,
    DateTime Function()? now,
  }) : _now = now;

  final ReceivedShare share;
  final VoidCallback onTap;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final accent = share.senderAccentColor;
    final preview = _titleOrPreview(share);
    final tagline = share.sender.signatureTagline;
    final ago = _relative(share.receivedAt, _now?.call() ?? DateTime.now());

    return Semantics(
      button: true,
      label: 'From ${share.sender.displayName}, $preview, received $ago',
      child: InkWell(
        onTap: onTap,
        borderRadius: tokens.shape.mdRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SenderChip(
                fill: accent,
                glyph: share.sender.signatureAccent,
                fallbackInitial: _initialFor(share.sender.displayName),
                // Resolve the foreground against the sender's accent so a
                // foreign palette never falls below the AA contrast floor —
                // `tokens.colors.onAccent` is calibrated for the receiver's
                // accent, not whatever swatch the sender chose.
                onAccent: clampForReadability(accent),
              ),
              Gap(tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${share.sender.displayName} · $preview',
                            style: tokens.text.bodyLg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Gap(tokens.spacing.sm),
                        Text(
                          ago,
                          style: tokens.text.labelSm.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (tagline.isNotEmpty) ...[
                      Gap(tokens.spacing.xs),
                      Text(
                        tagline,
                        style: tokens.text.bodySm.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SenderChip extends StatelessWidget {
  const _SenderChip({
    required this.fill,
    required this.glyph,
    required this.fallbackInitial,
    required this.onAccent,
  });

  final Color fill;
  final String? glyph;
  final String fallbackInitial;
  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = (glyph != null && glyph!.trim().isNotEmpty) ? glyph! : fallbackInitial;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: tokens.text.labelLg.copyWith(color: onAccent),
      ),
    );
  }
}

String _titleOrPreview(ReceivedShare share) {
  final title = share.note.title.trim();
  if (title.isNotEmpty) return title;
  for (final block in share.note.blocks) {
    final type = block['type'] as String?;
    if (type == 'text' || type == 'checklist') {
      final text = (block['text'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        return text.length <= 40 ? text : '${text.substring(0, 40)}…';
      }
    }
  }
  return 'Untitled note';
}

String _initialFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

String _relative(DateTime instant, DateTime now) {
  final diff = now.difference(instant);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  return '${diff.inDays ~/ 7} w';
}

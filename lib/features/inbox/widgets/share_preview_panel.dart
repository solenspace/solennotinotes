import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Renders a [ReceivedShare] read-only with the **sender's** App Style
/// chrome — palette, pattern backdrop, and signature tagline applied
/// via the same `applyToColors`/`applyToPatternBackdrop`/`applyToSignature`
/// recipe the editor uses on a live note. The user can either Accept
/// (merging into the library) or Discard.
class SharePreviewPanel extends StatelessWidget {
  const SharePreviewPanel({
    super.key,
    required this.share,
    required this.onAccept,
    required this.onDiscard,
  });

  final ReceivedShare share;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final baseTokens = context.tokens;
    final overlay = share.note.overlay;
    final patchedColors = overlay.applyToColors(baseTokens.colors);
    final patchedPattern = overlay.applyToPatternBackdrop(baseTokens.patternBackdrop);
    final patchedSignature = overlay.applyToSignature(baseTokens.signature);

    final themed = base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        patchedColors,
        baseTokens.text,
        baseTokens.motion,
        baseTokens.shape,
        baseTokens.elevation,
        baseTokens.spacing,
        patchedPattern,
        patchedSignature,
      ],
    );

    final isDarkSurface = patchedColors.surface.computeLuminance() < 0.5;

    return Theme(
      data: themed,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: patchedColors.surface,
          statusBarIconBrightness: isDarkSurface ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDarkSurface ? Brightness.dark : Brightness.light,
        ),
        child: Builder(
          builder: (themedCtx) {
            final tokens = themedCtx.tokens;
            return Scaffold(
              backgroundColor: tokens.colors.surface,
              appBar: AppBar(
                backgroundColor: tokens.colors.surfaceVariant,
                foregroundColor: tokens.colors.onSurface,
                surfaceTintColor: Colors.transparent,
                title: _PreviewSenderChip(sender: share.sender, accent: tokens.colors.accent),
                centerTitle: false,
              ),
              body: SafeArea(
                top: false,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    tokens.spacing.lg,
                    tokens.spacing.lg,
                    tokens.spacing.lg,
                    tokens.spacing.xl * 2,
                  ),
                  children: [
                    if (share.note.title.trim().isNotEmpty) ...[
                      Text(
                        share.note.title,
                        style: tokens.text.displaySm.copyWith(color: tokens.colors.onSurface),
                      ),
                      Gap(tokens.spacing.lg),
                    ],
                    for (final block in share.note.blocks) ...[
                      _BlockPreview(block: block, assets: share.assets, inboxRoot: share.inboxRoot),
                      Gap(tokens.spacing.sm),
                    ],
                    if (patchedSignature.tagline.isNotEmpty) ...[
                      Gap(tokens.spacing.lg),
                      Text(
                        patchedSignature.tagline,
                        style: tokens.text.bodySm.copyWith(
                          color: tokens.colors.onSurface.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(tokens.spacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: context.l10n.share_preview_discard_label,
                          child: OutlinedButton(
                            onPressed: onDiscard,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tokens.colors.error,
                              side: BorderSide(color: tokens.colors.error.withValues(alpha: 0.5)),
                              padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
                            ),
                            child: Text(context.l10n.common_discard),
                          ),
                        ),
                      ),
                      Gap(tokens.spacing.md),
                      Expanded(
                        flex: 2,
                        child: Semantics(
                          button: true,
                          label: context.l10n.share_preview_accept_label,
                          child: FilledButton(
                            onPressed: onAccept,
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.colors.accent,
                              foregroundColor: tokens.colors.onAccent,
                              padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
                            ),
                            child: Text(context.l10n.common_accept),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewSenderChip extends StatelessWidget {
  const _PreviewSenderChip({required this.sender, required this.accent});

  final IncomingSender sender;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final glyph = sender.signatureAccent;
    return Semantics(
      label: context.l10n.share_preview_from_semantic(sender.displayName),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null && glyph.trim().isNotEmpty) ...[
            Text(glyph, style: tokens.text.labelLg.copyWith(color: accent)),
            SizedBox(width: tokens.spacing.xs),
          ],
          Text(
            context.l10n.share_preview_from_caption(sender.displayName),
            style: tokens.text.labelMd.copyWith(color: tokens.colors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _BlockPreview extends StatelessWidget {
  const _BlockPreview({
    required this.block,
    required this.assets,
    required this.inboxRoot,
  });

  final Map<String, dynamic> block;
  final List<IncomingAsset> assets;
  final String inboxRoot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = block['type'] as String?;
    final textStyle = tokens.text.bodyLg.copyWith(color: tokens.colors.onSurface);
    switch (type) {
      case 'text':
        final text = (block['text'] as String? ?? '').trim();
        if (text.isEmpty) return const SizedBox.shrink();
        return Text(text, style: textStyle);
      case 'checklist':
        final text = (block['text'] as String? ?? '').trim();
        final checked = block['checked'] as bool? ?? false;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: tokens.colors.accent,
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Text(
                text,
                style: textStyle.copyWith(
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        );
      case 'image':
        final id = block['id'] as String?;
        final asset = _findAsset(id);
        if (asset == null) return const SizedBox.shrink();
        final file = File('$inboxRoot/${asset.pathInArchive}');
        return ClipRRect(
          borderRadius: tokens.shape.smRadius,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              color: tokens.colors.surfaceMuted,
              alignment: Alignment.center,
              child: Icon(Icons.broken_image_outlined, color: tokens.colors.onSurface),
            ),
          ),
        );
      case 'audio':
        final durationMs = (block['durationMs'] as num?)?.toInt() ?? 0;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.sm,
          ),
          decoration: BoxDecoration(
            color: tokens.colors.surfaceVariant,
            borderRadius: tokens.shape.smRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, color: tokens.colors.accent),
              SizedBox(width: tokens.spacing.sm),
              Text(
                context.l10n.share_preview_audio_duration(_formatDuration(durationMs)),
                style: tokens.text.labelMd,
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  IncomingAsset? _findAsset(String? id) {
    if (id == null) return null;
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }
}

String _formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

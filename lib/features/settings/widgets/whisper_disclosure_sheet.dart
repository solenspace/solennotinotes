import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../theme/tokens.dart';

/// Modal bottom sheet that asks the user to confirm the one-time
/// download of the on-device Whisper model file (Spec 21). Returns
/// `true` from [show] when the user taps Download, `false` (or `null`,
/// on swipe-to-dismiss) otherwise.
///
/// Mirrors [`AiDisclosureSheet`](ai_disclosure_sheet.dart) — kept as a
/// sibling rather than a generalisation because the copy + size figures
/// differ per model family. When a third on-device model lands, the
/// natural refactor is a shared base widget parameterised by `(title,
/// body, sizeMb)`.
class WhisperDisclosureSheet extends StatelessWidget {
  const WhisperDisclosureSheet({
    super.key,
    required this.approxMegabytes,
  });

  /// Approximate download size, surfaced in the body copy. Resolved
  /// from `WhisperModelConstants.specForTier(...)` at the call site so
  /// users on `AiTier.compact` see ~75 MB and users on `AiTier.full`
  /// see ~140 MB.
  final int approxMegabytes;

  static Future<bool?> show(
    BuildContext context, {
    required int approxMegabytes,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => WhisperDisclosureSheet(approxMegabytes: approxMegabytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          tokens.spacing.md,
          tokens.spacing.lg,
          tokens.spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: EdgeInsets.only(bottom: tokens.spacing.md),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.colors.divider,
                  borderRadius: tokens.shape.pillRadius,
                ),
              ),
            ),
            Text(
              'Enable voice transcription?',
              style: tokens.text.titleLg.copyWith(color: tokens.colors.onSurface),
            ),
            Gap(tokens.spacing.md),
            Text(
              'Voice transcription turns recorded audio notes into text using '
              'a small Whisper model that runs entirely on this device.',
              style: tokens.text.bodyMd.copyWith(color: tokens.colors.onSurface),
            ),
            Gap(tokens.spacing.sm),
            Text(
              'Notinotes will download the model file once (around '
              '$approxMegabytes MB). The download is a one-time, one-way '
              'connection. Audio never leaves your device — not now, not '
              'later. You can cancel any time.',
              style: tokens.text.bodyMd.copyWith(color: tokens.colors.onSurfaceMuted),
            ),
            Gap(tokens.spacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                Gap(tokens.spacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

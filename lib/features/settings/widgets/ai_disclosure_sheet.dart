import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../theme/tokens.dart';

/// Modal bottom sheet that asks the user to confirm the one-time download
/// of the on-device LLM model file. Returns `true` from [show] when the
/// user taps Download, `false` (or `null`, on swipe-to-dismiss) otherwise.
///
/// Copy is verbatim from Spec 19 § "Disclosure copy" with one number
/// updated: the spec text said "~700 MB" before the canonical GGUF size
/// was known; actual file is 668,788,096 bytes (~640 MB in the binary
/// units iOS / Android / macOS settings display under "Storage").
class AiDisclosureSheet extends StatelessWidget {
  const AiDisclosureSheet({super.key});

  /// Shows the sheet over [context]. Resolves to `true` iff the user opted
  /// in (Download). The cubit treats `null` and `false` identically — both
  /// leave the row in `idle`.
  static Future<bool?> show(BuildContext context) {
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
      builder: (_) => const AiDisclosureSheet(),
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
              'Enable AI assist?',
              style: tokens.text.titleLg.copyWith(color: tokens.colors.onSurface),
            ),
            Gap(tokens.spacing.md),
            Text(
              'The AI features summarize, rewrite, and suggest titles using a '
              'small language model that runs entirely on this device.',
              style: tokens.text.bodyMd.copyWith(color: tokens.colors.onSurface),
            ),
            Gap(tokens.spacing.sm),
            Text(
              'Notinotes will download the model file once (around 640 MB). '
              'The download is a one-time, one-way connection. Nothing else '
              'leaves your device — not now, not later. You can cancel any '
              'time.',
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

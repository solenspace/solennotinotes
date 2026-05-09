import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Shared bottom-sheet container. Provides a draggable handle, a title row,
/// safe-area padding, and consistent spacing.
class SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double? maxHeightFactor;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.maxHeightFactor = 0.85,
  });

  @override
  Widget build(BuildContext context) {
    final mediaH = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: mediaH * (maxHeightFactor ?? 0.85),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: SpacingPrimitives.lg,
          right: SpacingPrimitives.lg,
          top: SpacingPrimitives.sm,
          bottom: MediaQuery.of(context).viewInsets.bottom + SpacingPrimitives.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
            const Gap(SpacingPrimitives.md),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

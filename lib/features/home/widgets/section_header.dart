import 'package:flutter/material.dart';

import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Lightweight section title used between Pinned and Notes lists.
class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpacingPrimitives.lg,
        SpacingPrimitives.lg,
        SpacingPrimitives.lg,
        SpacingPrimitives.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

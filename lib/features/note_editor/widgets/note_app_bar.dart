import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:noti_notes_app/l10n/build_context_l10n.dart';

/// Slim editor app bar with back, pin, and overflow menu.
class NoteAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isPinned;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final VoidCallback? onShare;
  final Color? foregroundColor;
  final Color? backgroundColor;

  /// Optional title slot. Spec 11 wires the from-sender chip in here on
  /// shared notes; locally-authored notes pass null.
  final Widget? title;

  const NoteAppBar({
    super.key,
    required this.isPinned,
    required this.onTogglePin,
    required this.onDelete,
    this.onShare,
    this.foregroundColor,
    this.backgroundColor,
    this.title,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foregroundColor ?? scheme.onSurface;
    return AppBar(
      backgroundColor: backgroundColor ?? Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        tooltip: context.l10n.editor_back_tooltip,
        icon: Icon(Icons.arrow_back_rounded, color: fg),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: title,
      titleSpacing: 0,
      centerTitle: false,
      actions: [
        IconButton(
          tooltip: isPinned ? context.l10n.editor_unpin_tooltip : context.l10n.editor_pin_tooltip,
          icon: Icon(
            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            color: fg,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            onTogglePin();
          },
        ),
        PopupMenuButton<String>(
          tooltip: context.l10n.editor_more_tooltip,
          icon: Icon(Icons.more_horiz_rounded, color: fg),
          color: scheme.surfaceContainerHigh,
          onSelected: (value) {
            switch (value) {
              case 'delete':
                onDelete();
                break;
              case 'share':
                onShare?.call();
                break;
            }
          },
          itemBuilder: (context) => [
            if (onShare != null)
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(context.l10n.note_app_bar_share),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(
                  context.l10n.note_app_bar_delete,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

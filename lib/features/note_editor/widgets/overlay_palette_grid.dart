import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_palette_custom_picker.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// 4-column grid of curated palette tiles. The trailing tile opens the
/// custom HSL picker for users who want a one-off color. Selecting any
/// tile dispatches [OverlayPaletteChanged].
class OverlayPaletteGrid extends StatelessWidget {
  const OverlayPaletteGrid({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.note?.toOverlay() != b.note?.toOverlay(),
      builder: (ctx, state) {
        final selected = state.note?.toOverlay();
        return GridView.builder(
          controller: scrollController,
          padding: EdgeInsets.all(tokens.spacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: tokens.spacing.md,
            crossAxisSpacing: tokens.spacing.md,
            childAspectRatio: 1,
          ),
          itemCount: kCuratedPalettes.length + 1,
          itemBuilder: (gridCtx, index) {
            if (index == kCuratedPalettes.length) {
              return _CustomTile(
                onTap: () => _openCustomPicker(gridCtx),
              );
            }
            final overlay = kCuratedPalettes[index];
            final name = kCuratedPaletteNames[index];
            final isSelected = selected != null &&
                overlay.surface == selected.surface &&
                overlay.accent == selected.accent;
            return _PaletteTile(
              overlay: overlay,
              name: name,
              selected: isSelected,
              onTap: () => ctx.read<NoteEditorBloc>().add(OverlayPaletteChanged(overlay)),
            );
          },
        );
      },
    );
  }

  Future<void> _openCustomPicker(BuildContext gridCtx) async {
    final bloc = gridCtx.read<NoteEditorBloc>();
    final picked = await showModalBottomSheet<NotiThemeOverlay>(
      context: gridCtx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: gridCtx.tokens.colors.surface,
      builder: (_) => const OverlayPaletteCustomPicker(),
    );
    if (picked != null) {
      bloc.add(OverlayPaletteChanged(picked));
    }
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.overlay,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final NotiThemeOverlay overlay;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: '$name palette${selected ? ', selected' : ''}',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: tokens.shape.mdRadius,
        child: Container(
          decoration: BoxDecoration(
            color: overlay.surface,
            borderRadius: tokens.shape.mdRadius,
            border: Border.all(
              color: selected ? tokens.colors.onSurface : tokens.colors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          padding: EdgeInsets.all(tokens.spacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: overlay.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: overlay.onAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.labelMd.copyWith(
                  color: overlay.onSurface ??
                      (overlay.surface.computeLuminance() > 0.5
                          ? tokens.colors.inkOnLightSurface
                          : tokens.colors.inkOnDarkSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: 'Custom palette',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: tokens.shape.mdRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: tokens.shape.mdRadius,
            border: Border.all(
              color: tokens.colors.divider,
              style: BorderStyle.solid,
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.tune, color: tokens.colors.onSurfaceMuted),
              SizedBox(height: tokens.spacing.xs),
              Text(
                'Custom',
                style: tokens.text.labelMd.copyWith(color: tokens.colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// 3-column grid showing eight tiles: "None" + the seven bundled
/// [NotiPatternKey] PNGs. Each tile renders the pattern at body opacity
/// over the currently-selected palette's surface so the user previews the
/// actual outcome.
class OverlayPatternGrid extends StatelessWidget {
  const OverlayPatternGrid({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.note?.toOverlay() != b.note?.toOverlay(),
      builder: (ctx, state) {
        final overlay = state.note?.toOverlay();
        final surface = overlay?.surface ?? tokens.colors.surface;
        final selectedKey = overlay?.patternKey;

        final keys = <NotiPatternKey?>[null, ...NotiPatternKey.values];
        return GridView.builder(
          controller: scrollController,
          padding: EdgeInsets.all(tokens.spacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: tokens.spacing.md,
            crossAxisSpacing: tokens.spacing.md,
            childAspectRatio: 1,
          ),
          itemCount: keys.length,
          itemBuilder: (gridCtx, i) {
            final key = keys[i];
            final isSelected = key == selectedKey;
            return _PatternTile(
              patternKey: key,
              surface: surface,
              selected: isSelected,
              onTap: () => ctx.read<NoteEditorBloc>().add(OverlayPatternChanged(key)),
            );
          },
        );
      },
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.patternKey,
    required this.surface,
    required this.selected,
    required this.onTap,
  });

  final NotiPatternKey? patternKey;
  final Color surface;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = patternKey == null ? 'None' : _humanName(patternKey!);
    return Semantics(
      label: '$label pattern${selected ? ', selected' : ''}',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: tokens.shape.mdRadius,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: tokens.shape.mdRadius,
            border: Border.all(
              color: selected ? tokens.colors.onSurface : tokens.colors.divider,
              width: selected ? 2 : 1,
            ),
            image: patternKey == null
                ? null
                : DecorationImage(
                    image: AssetImage(patternKey!.assetPath),
                    fit: BoxFit.cover,
                    opacity: 0.30,
                  ),
          ),
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.all(tokens.spacing.sm),
          child: Text(
            label,
            style: tokens.text.labelMd.copyWith(
              color: surface.computeLuminance() > 0.5
                  ? tokens.colors.inkOnLightSurface
                  : tokens.colors.inkOnDarkSurface,
            ),
          ),
        ),
      ),
    );
  }

  String _humanName(NotiPatternKey key) {
    switch (key) {
      case NotiPatternKey.waves:
        return 'Waves';
      case NotiPatternKey.wavesUnregulated:
        return 'Waves (raw)';
      case NotiPatternKey.polygons:
        return 'Polygons';
      case NotiPatternKey.kaleidoscope:
        return 'Kaleidoscope';
      case NotiPatternKey.splashes:
        return 'Splashes';
      case NotiPatternKey.noise:
        return 'Noise';
      case NotiPatternKey.upScaleWaves:
        return 'Up-scale Waves';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/services/speech/tts_models.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Floating control rendered above the editor toolbar while the
/// synthesizer is reading. Shows the active block's text with the current
/// word highlighted in `tokens.colors.accent`, and surfaces pause/resume
/// + stop affordances. Renders nothing when `state.isReadingAloud` is
/// false. Sibling to `_DictationDraftBanner` in the same column slot.
class ReadAloudOverlay extends StatelessWidget {
  const ReadAloudOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) =>
          a.isReadingAloud != b.isReadingAloud ||
          a.isReadAloudPaused != b.isReadAloudPaused ||
          a.currentReadBlockIndex != b.currentReadBlockIndex ||
          a.readProgress != b.readProgress,
      builder: (context, state) {
        if (!state.isReadingAloud) return const SizedBox.shrink();
        return _OverlayPill(
          paused: state.isReadAloudPaused,
          blockIndex: state.currentReadBlockIndex,
          totalBlocks: _readableBlockCount(state),
          progress: state.readProgress,
        );
      },
    );
  }

  /// Counts text + non-empty checklist blocks on the current note. Used
  /// only for the overlay's "Reading block N of M" copy. Mirrors the
  /// bloc's `_readableBlocks` filter without exposing it.
  int _readableBlockCount(NoteEditorState state) {
    final note = state.note;
    if (note == null) return 0;
    var count = 0;
    for (final b in note.blocks) {
      final type = b['type'];
      final text = (b['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      if (type == 'text' || type == 'checklist') count++;
    }
    return count;
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({
    required this.paused,
    required this.blockIndex,
    required this.totalBlocks,
    required this.progress,
  });

  final bool paused;
  final int? blockIndex;
  final int totalBlocks;
  final TtsProgress? progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final indexLabel = (blockIndex == null || totalBlocks == 0)
        ? context.l10n.read_aloud_reading
        : context.l10n.read_aloud_block_count(blockIndex! + 1, totalBlocks);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.xs,
      ),
      child: Semantics(
        container: true,
        // liveRegion announces the block label changes (block N of M) but
        // the rendered word-by-word text is muted to assistive tech via
        // `excludeSemantics`, so VoiceOver/TalkBack does not double-read
        // what the synthesizer is already saying.
        liveRegion: true,
        label: indexLabel,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.sm,
          ),
          decoration: BoxDecoration(
            color: tokens.colors.surfaceVariant.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            border: Border.all(
              color: tokens.colors.accent.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 16,
                    color: tokens.colors.accent,
                  ),
                  Gap(tokens.spacing.xs),
                  Expanded(
                    child: Text(
                      indexLabel,
                      style: tokens.text.labelSm.copyWith(
                        color: tokens.colors.onSurfaceMuted,
                      ),
                    ),
                  ),
                ],
              ),
              Gap(tokens.spacing.xs),
              ExcludeSemantics(
                child: _HighlightedText(
                  progress: progress,
                  baseColor: tokens.colors.onSurface,
                  accentColor: tokens.colors.accent,
                  baseStyle: tokens.text.bodySm,
                ),
              ),
              Gap(tokens.spacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _PillIconButton(
                    tooltip: paused
                        ? context.l10n.read_aloud_resume_tooltip
                        : context.l10n.read_aloud_pause_tooltip,
                    icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: tokens.colors.onSurface,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final bloc = context.read<NoteEditorBloc>();
                      if (paused) {
                        bloc.add(const ReadAloudResumed());
                      } else {
                        bloc.add(const ReadAloudPaused());
                      }
                    },
                  ),
                  Gap(tokens.spacing.xs),
                  _PillIconButton(
                    tooltip: context.l10n.read_aloud_stop,
                    icon: Icons.stop_rounded,
                    color: tokens.colors.onSurface,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<NoteEditorBloc>().add(const ReadAloudStopped());
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the current block's text as three spans — `[before, active,
/// after]` — using `progress.start` and `progress.end` to slice. When
/// progress is null (between blocks or just-started), shows the full text
/// in `baseColor` so the user always sees what's about to be read.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.progress,
    required this.baseColor,
    required this.accentColor,
    required this.baseStyle,
  });

  final TtsProgress? progress;
  final Color baseColor;
  final Color accentColor;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) {
      return Text(
        '…',
        style: baseStyle.copyWith(color: baseColor.withValues(alpha: 0.6)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    final text = p.text;
    // The plugin's offsets are best-effort and can occasionally fall
    // outside `[0, text.length]` for emoji-heavy strings; clamp so a bad
    // sample never throws on the slice.
    final start = p.start.clamp(0, text.length);
    final end = p.end.clamp(start, text.length);
    final before = text.substring(0, start);
    final active = text.substring(start, end);
    final after = text.substring(end);
    return Text.rich(
      TextSpan(
        style: baseStyle.copyWith(color: baseColor),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: active,
            style: baseStyle.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Padding(
            // 44x44 tap target: 22px icon + 11px padding × 2
            padding: const EdgeInsets.all(11),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

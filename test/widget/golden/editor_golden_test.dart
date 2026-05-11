import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/tokens.dart';

import '_fixtures/fixture_notes.dart';
import '_helpers/pump_scene.dart';
import '_helpers/variants.dart';

/// Editor scene goldens. The full `NoteEditorScreen` mounts a chain of
/// service-bound cubits (AI assist, Whisper readiness, image picker, audio
/// capture) that have no place in a visual regression test — they
/// orchestrate behavior, not pixels. The body of [`_EditorScene`] mirrors
/// the production layout in [`note_editor/screen.dart:495+`] (themed
/// Scaffold + title + block list + accent-tinted toolbar bar) so every
/// `NoteColors` / `NotiText` / `NotiSpacing` / `NotiShape` / `NotiSignature`
/// consumer the editor actually exercises shows up in the golden.
///
/// Matrix: 2 base brightnesses + 12 palettes + 7 patterns = 21 PNGs.
void main() {
  group('Editor goldens', () {
    final variants = [...palettesOnly(), ...patternsOnOnyx()];
    for (final variant in variants) {
      testWidgets('editor — ${variant.slug}', (tester) async {
        await pumpScene(
          tester,
          theme: variant.themeBuilder(),
          child: const _EditorScene(),
        );
        await expectLater(
          find.byType(_EditorScene),
          matchesGoldenFile('../../goldens/editor/${variant.slug}.png'),
        );
      });
    }
  });
}

class _EditorScene extends StatelessWidget {
  const _EditorScene();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final note = fixtureNoteA();
    final patternKey = NotiPatternKey.fromString(tokens.patternBackdrop.patternKey);
    return _PatternedSurface(
      patternKey: patternKey,
      bodyOpacity: tokens.patternBackdrop.bodyOpacity,
      child: Scaffold(
        backgroundColor: patternKey == null ? colors.surface : Colors.transparent,
        appBar: AppBar(
          backgroundColor: colors.surface,
          foregroundColor: colors.onSurface,
          elevation: 0,
          title: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
              ),
              const Gap(8),
              Text('Editor', style: tokens.text.titleMd.copyWith(color: colors.onSurface)),
            ],
          ),
          actions: [
            Icon(Icons.push_pin_outlined, color: colors.onSurface),
            const Gap(8),
            Icon(Icons.more_horiz_rounded, color: colors.onSurface),
            const Gap(12),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.lg,
              vertical: tokens.spacing.lg,
            ),
            children: [
              Text(
                note.title,
                style: tokens.text.displaySm.copyWith(color: colors.onSurface),
              ),
              Gap(tokens.spacing.md),
              for (final b in note.blocks) ...[
                _Block(block: b),
                Gap(tokens.spacing.sm),
              ],
              Gap(tokens.spacing.xl),
              _ToolbarBar(),
            ],
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          child: const Icon(Icons.check_rounded),
        ),
      ),
    );
  }
}

class _PatternedSurface extends StatelessWidget {
  const _PatternedSurface({
    required this.patternKey,
    required this.bodyOpacity,
    required this.child,
  });

  final NotiPatternKey? patternKey;
  final double bodyOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (patternKey == null) return child;
    final colors = context.tokens.colors;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: colors.surface)),
        Positioned.fill(
          child: Opacity(
            opacity: bodyOpacity.clamp(0.0, 1.0),
            child: Image.asset(patternKey!.assetPath, fit: BoxFit.cover),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});
  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final type = block['type'] as String?;
    final text = (block['text'] as String? ?? '').trim();
    final textStyle = tokens.text.bodyLg.copyWith(color: colors.onSurface);
    switch (type) {
      case 'checklist':
        final checked = block['checked'] as bool? ?? false;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: colors.accent,
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
      case 'text':
      default:
        return Text(text, style: textStyle);
    }
  }
}

class _ToolbarBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: tokens.shape.smRadius,
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.format_list_bulleted, color: colors.onSurface),
          const Gap(16),
          Icon(Icons.mic_rounded, color: colors.onSurface),
          const Gap(16),
          Icon(Icons.image_outlined, color: colors.onSurface),
          const Gap(16),
          Icon(Icons.format_paint_outlined, color: colors.accent),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.2),
              borderRadius: tokens.shape.pillRadius,
            ),
            child: Text(
              '✦ aa',
              style: tokens.text.labelSm.copyWith(color: colors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

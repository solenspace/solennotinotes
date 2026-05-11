import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/features/note_editor/widgets/ai_assist_sheet.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// The "✦ Assist" button mounted in the editor toolbar. Hidden whenever
/// either gate is unmet:
///
///   * `DeviceCapabilityService.aiTier.canRunLlm` is `false` (Spec 17),
///     OR
///   * `LlmReadinessCubit` reports anything other than
///     [LlmReadinessPhase.ready] (Spec 19).
///
/// On tap → opens [AiAssistSheet]. On long-press → navigates to
/// [ManageAiScreen] so the user can re-download or delete the model
/// without leaving the editor (Spec 20 § "The ✦ Assist toolbar button").
///
/// Visual chrome mirrors `EditorToolbar._ToolButton` (40×40 container,
/// 22 px glyph, `RadiusPrimitives.sm`, AnimatedScale press feedback)
/// rather than depending on it directly — the toolbar's button is
/// private to its file, and a public extraction is out of scope here.
class AiAssistButton extends StatelessWidget {
  const AiAssistButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<LlmReadinessCubit, LlmReadinessState, bool>(
      selector: (s) => s.phase == LlmReadinessPhase.ready,
      builder: (ctx, ready) {
        final tier = ctx.read<DeviceCapabilityService>().aiTier;
        if (!tier.canRunLlm || !ready) return const SizedBox.shrink();
        return const _AssistToolButton();
      },
    );
  }
}

class _AssistToolButton extends StatefulWidget {
  const _AssistToolButton();

  @override
  State<_AssistToolButton> createState() => _AssistToolButtonState();
}

class _AssistToolButtonState extends State<_AssistToolButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = context.tokens.signature.accent ?? '✦';
    return Tooltip(
      message: context.l10n.ai_assist_tooltip,
      child: Semantics(
        label: context.l10n.ai_assist_label,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.selectionClick();
            AiAssistSheet.show(context);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            Navigator.of(context).pushNamed(ManageAiScreen.routeName);
          },
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: DurationPrimitives.fast,
            curve: CurvePrimitives.calm,
            child: AnimatedContainer(
              duration: DurationPrimitives.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.0,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

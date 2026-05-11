import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Renders the live-streaming pane Spec 20 § "Streaming UX" describes:
///
///   * The user's `signatureAccent` glyph (or `✦`) gently pulses at
///     the top while [AiAssistState.isGenerating] is true — visual
///     proof the model is alive.
///   * The accumulating [AiAssistState.draftOutput] is displayed inside
///     a `Semantics(liveRegion: true)` so VoiceOver / TalkBack
///     announce it as it grows. A blinking `▎` cursor sits at the end
///     while generation is in flight.
///   * A "First token in 5–15 seconds" hint surfaces while we are
///     generating but no token has arrived yet — Spec 20 § "Latency
///     feedback" calls this out as the antidote to "the app froze"
///     panic on slower devices.
///   * Elapsed wall-clock time renders in the bottom-right.
///
/// Pure presentational widget: it never calls into the cubit. The
/// owning sheet is responsible for the Stop button + accept paths.
class AiStreamingPane extends StatelessWidget {
  const AiStreamingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AiAssistCubit, AiAssistState>(
      builder: (context, state) {
        final tokens = context.tokens;
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SignaturePulse(active: state.isGenerating),
              Gap(tokens.spacing.md),
              if (state.errorMessage != null)
                _ErrorBox(message: state.errorMessage!)
              else
                Expanded(child: _DraftBody(state: state)),
              Gap(tokens.spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatElapsed(state.elapsed),
                    style: tokens.text.labelSm.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatElapsed(Duration d) {
    final seconds = d.inSeconds % 60;
    final minutes = d.inMinutes;
    final ss = seconds.toString().padLeft(2, '0');
    return '$minutes:$ss';
  }
}

class _DraftBody extends StatelessWidget {
  const _DraftBody({required this.state});
  final AiAssistState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final isWaiting = state.isGenerating && !state.firstTokenArrived;

    if (isWaiting) {
      return Center(
        child: Text(
          context.l10n.ai_streaming_first_token_hint,
          style: tokens.text.bodyMd.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      child: SingleChildScrollView(
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(text: state.draftOutput),
              if (state.isGenerating)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _BlinkingCursor(color: scheme.onSurface),
                ),
            ],
            style: tokens.text.bodyLg.copyWith(color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _SignaturePulse extends StatefulWidget {
  const _SignaturePulse({required this.active});
  final bool active;

  @override
  State<_SignaturePulse> createState() => _SignaturePulseState();
}

class _SignaturePulseState extends State<_SignaturePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant _SignaturePulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final glyph = tokens.signature.accent ?? '✦';
    return Center(
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.12).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 32,
            color: scheme.primary,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});
  final Color color;

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> {
  bool _on = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _on ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 80),
      child: Text(
        '▎',
        style: TextStyle(color: widget.color, fontSize: 16),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 18),
          Gap(tokens.spacing.sm),
          Expanded(
            child: Text(
              message,
              style: tokens.text.bodyMd.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Inline playback pill for an [AudioBlock]. Renders the pre-computed
/// 80-bucket waveform with a playhead overlay; tap toggles play/pause;
/// long-press opens a context menu (`Transcribe` (Spec 21, conditional),
/// `Re-record`, `Delete`).
class AudioBlockView extends StatefulWidget {
  const AudioBlockView({
    super.key,
    required this.block,
    required this.onDelete,
    required this.onReRecord,
    this.onTranscribe,
  });

  final AudioBlock block;
  final VoidCallback onDelete;
  final VoidCallback onReRecord;

  /// Spec 21 — when non-null, the long-press menu surfaces a
  /// "Transcribe" entry that invokes this callback. The screen wires
  /// the callback only when `aiTier.canRunWhisper` AND
  /// `WhisperReadinessCubit == ready` (otherwise null hides the entry
  /// entirely; users on unsupported devices or without the model
  /// downloaded see the existing menu unchanged).
  final VoidCallback? onTranscribe;

  @override
  State<AudioBlockView> createState() => _AudioBlockViewState();
}

class _AudioBlockViewState extends State<AudioBlockView> {
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _toggle() async {
    unawaited(HapticFeedback.selectionClick());
    if (_playing) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(widget.block.path));
      if (!mounted) return;
      setState(() => _playing = true);
    }
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    unawaited(HapticFeedback.mediumImpact());
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        if (widget.onTranscribe != null)
          const PopupMenuItem<String>(
            value: 'transcribe',
            child: Text('Transcribe'),
          ),
        const PopupMenuItem<String>(value: 're-record', child: Text('Re-record')),
        const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'transcribe':
        await _player.stop();
        widget.onTranscribe?.call();
      case 're-record':
        await _player.stop();
        widget.onReRecord();
      case 'delete':
        await _player.stop();
        widget.onDelete();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  double get _progress {
    final total = widget.block.durationMs;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  String _formatDuration(int ms) {
    final total = Duration(milliseconds: ms);
    final m = total.inMinutes;
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semanticLabel = _playing
        ? 'Audio playing, ${_formatDuration(_position.inMilliseconds)} of '
            '${_formatDuration(widget.block.durationMs)}. Long-press for options.'
        : 'Audio paused, ${_formatDuration(widget.block.durationMs)} total. '
            'Long-press for options.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingPrimitives.sm),
      child: Semantics(
        container: true,
        label: semanticLabel,
        liveRegion: true,
        child: GestureDetector(
          onLongPressStart: (details) => _showContextMenu(details.globalPosition),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: SpacingPrimitives.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _playing ? 'Pause' : 'Play',
                  onPressed: _toggle,
                  icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  color: scheme.onSurface,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                const Gap(SpacingPrimitives.sm),
                Expanded(
                  child: CustomPaint(
                    size: const Size.fromHeight(32),
                    painter: _WaveformPainter(
                      peaks: widget.block.amplitudePeaks,
                      progress: _progress,
                      activeColor: scheme.primary,
                      inactiveColor: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const Gap(SpacingPrimitives.sm),
                Text(
                  _formatDuration(widget.block.durationMs),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                if (widget.block.truncated) ...[
                  const Gap(SpacingPrimitives.xs),
                  Tooltip(
                    message: 'Recording exceeded 10 MB cap',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: scheme.error.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final barWidth = size.width / peaks.length;
    final mid = size.height / 2;
    final activeUpTo = (peaks.length * progress).floor();
    for (var i = 0; i < peaks.length; i++) {
      final paint = Paint()
        ..color = i < activeUpTo ? activeColor : inactiveColor
        ..strokeWidth = (barWidth * 0.6).clamp(1.0, 3.0)
        ..strokeCap = StrokeCap.round;
      final h = (peaks[i].clamp(0.0, 1.0)) * size.height * 0.9;
      final x = i * barWidth + barWidth / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.peaks != peaks ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}

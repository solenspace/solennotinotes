import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_accent_picker.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_palette_grid.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_pattern_grid.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Three-tab modal bottom sheet — Palette / Pattern / Accent — invoked
/// from the editor toolbar's paintbrush. Snaps at 0.5 (initial) and 0.92
/// (drag-up) of screen height.
///
/// Mounted via [show] which threads the editor's existing
/// [NoteEditorBloc] through [BlocProvider.value] so each tab can dispatch
/// overlay events to the same instance.
class OverlayPickerSheet extends StatefulWidget {
  const OverlayPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    final bloc = context.read<NoteEditorBloc>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: const OverlayPickerSheet(),
      ),
    );
  }

  @override
  State<OverlayPickerSheet> createState() => _OverlayPickerSheetState();
}

class _OverlayPickerSheetState extends State<OverlayPickerSheet> with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const _DragHandle(),
          TabBar(
            controller: _tabs,
            indicatorColor: tokens.colors.accent,
            labelColor: tokens.colors.onSurface,
            unselectedLabelColor: tokens.colors.onSurfaceMuted,
            tabs: const [
              Tab(text: 'Palette'),
              Tab(text: 'Pattern'),
              Tab(text: 'Accent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                OverlayPaletteGrid(scrollController: scroll),
                OverlayPatternGrid(scrollController: scroll),
                OverlayAccentPicker(scrollController: scroll),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: tokens.colors.divider,
        borderRadius: tokens.shape.pillRadius,
      ),
    );
  }
}

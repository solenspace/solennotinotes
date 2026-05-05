import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:noti_notes_app/features/note_editor/screen.dart';
import 'package:noti_notes_app/features/search/cubit/search_cubit.dart';
import 'package:noti_notes_app/features/search/cubit/search_state.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/app_tokens.dart';

import 'bloc/notes_list_bloc.dart';
import 'bloc/notes_list_state.dart';
import 'widgets/empty_state.dart';
import 'widgets/expandable_fab.dart';
import 'widgets/filter_chips_row.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/long_press_menu_sheet.dart';
import 'widgets/note_card.dart';
import 'widgets/section_header.dart';

class HomeScreen extends StatefulWidget {
  static const routeName = '/home-screen';
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Apply title search and filter chip to the visible note list.
  List<Note> _applyFilters(List<Note> source, SearchState search) {
    Iterable<Note> result = source;
    if (search.query.isNotEmpty) {
      final q = search.query.toLowerCase();
      result = result.where((n) => n.title.toLowerCase().contains(q));
    }
    switch (search.filter) {
      case NoteFilter.all:
        break;
      case NoteFilter.reminders:
        result = result.where((n) => n.reminder != null);
        break;
      case NoteFilter.checklists:
        result = result.where((n) => n.blocks.any((b) => b['type'] == 'checklist'));
        break;
      case NoteFilter.images:
        result = result.where(
          (n) => n.blocks.any((b) => b['type'] == 'image') || n.imageFile != null,
        );
        break;
    }
    return result.toList();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchCubit>().state;

    return BlocBuilder<NotesListBloc, NotesListState>(
      builder: (context, state) {
        final pinned = _applyFilters(state.pinnedNotes, search);
        final unpinned = _applyFilters(state.unpinnedNotes, search);
        final isEmpty = pinned.isEmpty && unpinned.isEmpty;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              const HomeAppBar(),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              const SliverToBoxAdapter(child: FilterChipsRow()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              if (isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(),
                )
              else ...[
                if (pinned.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('Pinned')),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childCount: pinned.length,
                      itemBuilder: (context, i) => _buildAnimated(
                        context,
                        pinned[i],
                        i,
                      ),
                    ),
                  ),
                ],
                if (unpinned.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      pinned.isNotEmpty ? 'Notes' : 'All notes',
                    ),
                  ),
                if (unpinned.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childCount: unpinned.length,
                      itemBuilder: (context, i) => _buildAnimated(
                        context,
                        unpinned[i],
                        pinned.length + i,
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ExpandableFab(
              onContent: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
                );
                if (mounted) setState(() {});
              },
              onTodo: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NoteEditorScreen(noteType: NoteType.todo),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimated(BuildContext context, Note note, int index) {
    return _buildOpenContainerCard(context, note)
        .animate()
        .fadeIn(
          duration: AppDurations.md,
          delay: Duration(milliseconds: 40 * index),
          curve: AppCurves.standard,
        )
        .slideY(
          begin: 0.08,
          end: 0,
          duration: AppDurations.md,
          delay: Duration(milliseconds: 40 * index),
          curve: AppCurves.standard,
        );
  }

  Widget _buildOpenContainerCard(BuildContext context, Note note) {
    return OpenContainer(
      closedElevation: 0,
      openElevation: 0,
      closedColor: note.hasGradient ? note.colorBackground : note.colorBackground,
      openColor: Theme.of(context).colorScheme.surface,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      transitionDuration: AppDurations.md,
      transitionType: ContainerTransitionType.fadeThrough,
      closedBuilder: (context, openContainer) => NoteCard(
        note: note,
        onTap: openContainer,
        onLongPress: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => LongPressMenuSheet(noteId: note.id),
        ),
      ),
      openBuilder: (context, _) => NoteEditorScreen(noteId: note.id),
    );
  }
}

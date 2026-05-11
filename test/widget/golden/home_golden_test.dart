import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/home/bloc/notes_list_bloc.dart';
import 'package:noti_notes_app/features/home/widgets/note_card.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

import '../../repositories/notes/fake_notes_repository.dart';
import '_fixtures/fixture_notes.dart';
import '_helpers/pump_scene.dart';
import '_helpers/variants.dart';

/// Renders the home masonry grid populated with three fixture notes across
/// every theme variant. The three [NoteCard] widgets exercise every visual
/// token consumer on the home surface (background, accent dot, ink,
/// shape, spacing, text styles, divider).
void main() {
  group('Home goldens', () {
    for (final variant in palettesOnly()) {
      testWidgets('home — ${variant.slug}', (tester) async {
        final repo = FakeNotesRepository();
        final notes =
            variant.overlay == null ? fixtureNotes() : fixtureNotesWithOverlay(variant.overlay!);
        repo.emit(notes);
        addTearDown(repo.dispose);

        await pumpScene(
          tester,
          theme: variant.themeBuilder(),
          child: _HomeScene(repository: repo, notes: notes),
        );

        await expectLater(
          find.byType(_HomeScene),
          matchesGoldenFile('../../goldens/home/${variant.slug}.png'),
        );
      });
    }
  });
}

class _HomeScene extends StatelessWidget {
  const _HomeScene({required this.repository, required this.notes});

  final FakeNotesRepository repository;
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotesListBloc>(
      create: (_) => NotesListBloc(
        repository: repository,
        cancelNotification: (_) {},
      ),
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: Gap(SpacingPrimitives.md)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingPrimitives.lg),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: SpacingPrimitives.md,
                  crossAxisSpacing: SpacingPrimitives.md,
                  childCount: notes.length,
                  itemBuilder: (_, i) => NoteCard(
                    note: notes[i],
                    onTap: () {},
                    onLongPress: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

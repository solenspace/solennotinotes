import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/search/cubit/search_cubit.dart';
import 'package:noti_notes_app/features/search/cubit/search_state.dart';

void main() {
  group('SearchCubit', () {
    test('starts in not-searching with empty query, no tags, all-filter', () {
      final cubit = SearchCubit();
      expect(cubit.state.type, SearchType.notSearching);
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.tags, isEmpty);
      expect(cubit.state.filter, NoteFilter.all);
      cubit.close();
    });

    test('activateByTitle sets type to searchingByTitle', () {
      final cubit = SearchCubit()..activateByTitle();
      expect(cubit.state.type, SearchType.searchingByTitle);
      cubit.close();
    });

    test('activateByTag sets type to searchingByTag', () {
      final cubit = SearchCubit()..activateByTag();
      expect(cubit.state.type, SearchType.searchingByTag);
      cubit.close();
    });

    test('deactivate resets type, query, and tags', () {
      final cubit = SearchCubit()
        ..activateByTitle()
        ..setQuery('hello')
        ..addTag('work');
      expect(cubit.state.query, 'hello');
      expect(cubit.state.tags, {'work'});

      cubit.deactivate();
      expect(cubit.state.type, SearchType.notSearching);
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.tags, isEmpty);
      cubit.close();
    });

    test('setQuery stores the new query without changing type', () {
      final cubit = SearchCubit()
        ..activateByTitle()
        ..setQuery('todo');
      expect(cubit.state.query, 'todo');
      expect(cubit.state.type, SearchType.searchingByTitle);
      cubit.close();
    });

    test('setFilter changes the filter chip', () {
      final cubit = SearchCubit()..setFilter(NoteFilter.reminders);
      expect(cubit.state.filter, NoteFilter.reminders);

      cubit.setFilter(NoteFilter.images);
      expect(cubit.state.filter, NoteFilter.images);
      cubit.close();
    });

    test('addTag adds the tag and auto-activates searchingByTag', () {
      final cubit = SearchCubit()..addTag('work');
      expect(cubit.state.tags, {'work'});
      expect(cubit.state.type, SearchType.searchingByTag);

      cubit.addTag('home');
      expect(cubit.state.tags, {'work', 'home'});
      expect(cubit.state.type, SearchType.searchingByTag);
      cubit.close();
    });

    test('removeTag drops the tag and deactivates when the set empties', () {
      final cubit = SearchCubit()
        ..addTag('a')
        ..addTag('b');

      cubit.removeTag('a');
      expect(cubit.state.tags, {'b'});
      expect(cubit.state.type, SearchType.searchingByTag);

      cubit.removeTag('b');
      expect(cubit.state.tags, isEmpty);
      expect(cubit.state.type, SearchType.notSearching);
      cubit.close();
    });
  });
}

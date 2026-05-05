import 'package:bloc/bloc.dart';

import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit() : super(const SearchState());

  void activateByTitle() => emit(state.copyWith(type: SearchType.searchingByTitle));

  void activateByTag() => emit(state.copyWith(type: SearchType.searchingByTag));

  void deactivate() {
    emit(
      state.copyWith(
        type: SearchType.notSearching,
        query: '',
        tags: const {},
      ),
    );
  }

  void setQuery(String q) => emit(state.copyWith(query: q));

  void setFilter(NoteFilter f) => emit(state.copyWith(filter: f));

  void addTag(String tag) {
    final next = {...state.tags, tag};
    emit(state.copyWith(tags: next, type: SearchType.searchingByTag));
  }

  void removeTag(String tag) {
    final next = {...state.tags}..remove(tag);
    emit(
      state.copyWith(
        tags: next,
        type: next.isEmpty ? SearchType.notSearching : SearchType.searchingByTag,
      ),
    );
  }
}

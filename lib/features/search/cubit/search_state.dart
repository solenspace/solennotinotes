import 'package:equatable/equatable.dart';

enum SearchType { notSearching, searchingByTitle, searchingByTag }

/// Top-bar filter chips on the home screen.
enum NoteFilter { all, reminders, checklists, images }

class SearchState extends Equatable {
  const SearchState({
    this.type = SearchType.notSearching,
    this.query = '',
    this.tags = const {},
    this.filter = NoteFilter.all,
  });

  final SearchType type;
  final String query;
  final Set<String> tags;
  final NoteFilter filter;

  SearchState copyWith({
    SearchType? type,
    String? query,
    Set<String>? tags,
    NoteFilter? filter,
  }) {
    return SearchState(
      type: type ?? this.type,
      query: query ?? this.query,
      tags: tags ?? this.tags,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [type, query, tags, filter];
}

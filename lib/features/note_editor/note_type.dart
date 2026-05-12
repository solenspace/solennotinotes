/// Seed shape for a fresh editor session. `content` opens with a single
/// text block; `todo` opens with a single empty checklist block and the
/// note's [DisplayMode.withTodoList] hint; `audio` opens with a single text
/// block and immediately triggers the audio capture flow.
enum NoteType { content, todo, audio }

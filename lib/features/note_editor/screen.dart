import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/theme/app_tokens.dart';
import 'package:noti_notes_app/theme/notes_color_palette.dart';

import 'bloc/note_editor_bloc.dart';
import 'bloc/note_editor_event.dart';
import 'bloc/note_editor_state.dart';
import 'note_type.dart';
import 'widgets/checklist_block.dart';
import 'widgets/editor_block.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/image_block.dart';
import 'widgets/note_app_bar.dart';
import 'widgets/note_style_sheet.dart';
import 'widgets/reminder_sheet.dart';
import 'widgets/tag_sheet.dart';
import 'widgets/text_block.dart';

export 'note_type.dart';

/// The unified, single-screen note editor. Mounts a per-route
/// [NoteEditorBloc] and delegates rendering to [_NoteEditorView]; the BLoC
/// is disposed when the route pops.
class NoteEditorScreen extends StatelessWidget {
  static const routeName = '/note-editor';

  /// If non-null, edit an existing note. If null, a new note is created
  /// and persisted on the first content-bearing event.
  final String? noteId;

  /// The seed shape for new notes. Ignored when [noteId] is non-null.
  final NoteType noteType;

  const NoteEditorScreen({super.key, this.noteId, this.noteType = NoteType.content});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NoteEditorBloc>(
      create: (ctx) => NoteEditorBloc(repository: ctx.read<NotesRepository>())
        ..add(EditorOpened(noteId: noteId, noteType: noteType)),
      child: _NoteEditorView(noteType: noteType),
    );
  }
}

class _NoteEditorView extends StatefulWidget {
  const _NoteEditorView({required this.noteType});

  final NoteType noteType;

  @override
  State<_NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends State<_NoteEditorView> {
  late final TextEditingController _titleController = TextEditingController();
  List<EditorBlock> _blocks = const [];
  final Map<String, FocusNode> _focusNodes = {};
  String? _focusedBlockId;
  bool _initialized = false;

  @override
  void dispose() {
    _titleController.dispose();
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _focusFor(String id) => _focusNodes.putIfAbsent(
        id,
        () => FocusNode()
          ..addListener(() {
            if (_focusNodes[id]?.hasFocus == true) {
              setState(() => _focusedBlockId = id);
            }
          }),
      );

  void _focusBlock(String id) {
    _focusFor(id).requestFocus();
    setState(() => _focusedBlockId = id);
  }

  void _initializeFromNote(Note note) {
    _titleController.text = note.title;
    _blocks = note.blocks.isEmpty
        ? (widget.noteType == NoteType.todo ? [newChecklistBlock()] : [newTextBlock()])
        : note.blocks.map(EditorBlock.fromMap).toList();
    _initialized = true;
    if (note.title.isEmpty && note.blocks.isEmpty) {
      // New note → autofocus the first block after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _blocks.isEmpty) return;
        _focusBlock(_blocks.first.id);
      });
    }
  }

  void _persistBlocks() {
    context.read<NoteEditorBloc>().add(BlocksReplaced(_blocks.map((b) => b.toMap()).toList()));
  }

  void _onBlockChanged() => _persistBlocks();

  void _insertTextBlockBelow(String afterId, String text) {
    final i = _blocks.indexWhere((b) => b.id == afterId);
    if (i < 0) return;
    final newBlock = newTextBlock(text);
    setState(() => _blocks.insert(i + 1, newBlock));
    _persistBlocks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusBlock(newBlock.id);
    });
  }

  void _insertChecklistBlockBelow(String afterId, String text) {
    final i = _blocks.indexWhere((b) => b.id == afterId);
    if (i < 0) return;
    final newBlock = newChecklistBlock(text);
    setState(() => _blocks.insert(i + 1, newBlock));
    _persistBlocks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusBlock(newBlock.id);
    });
  }

  void _deleteBlock(String id) {
    final i = _blocks.indexWhere((b) => b.id == id);
    if (i < 0 || _blocks.length == 1) return;
    setState(() => _blocks.removeAt(i));
    _persistBlocks();
    final focusIndex = (i - 1).clamp(0, _blocks.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _blocks.isEmpty) return;
      _focusBlock(_blocks[focusIndex].id);
    });
  }

  void _convertCurrentBlock() {
    final id = _focusedBlockId ?? (_blocks.isNotEmpty ? _blocks.first.id : null);
    if (id == null) return;
    final i = _blocks.indexWhere((b) => b.id == id);
    if (i < 0) return;
    final current = _blocks[i];
    EditorBlock replacement;
    if (current is TextBlock) {
      replacement = ChecklistBlock(id: current.id, text: current.text);
    } else if (current is ChecklistBlock) {
      replacement = TextBlock(id: current.id, text: current.text);
    } else {
      return;
    }
    setState(() => _blocks[i] = replacement);
    _persistBlocks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusBlock(replacement.id);
    });
  }

  Future<void> _addImage() async {
    final picked = await const ImagePickerService().pickImage(ImageSource.gallery, 80);
    if (picked == null) return;
    final block = newImageBlock(picked.path);
    setState(() => _blocks.add(block));
    _persistBlocks();
  }

  void _deleteImageBlock(String id) {
    final i = _blocks.indexWhere((b) => b.id == id);
    if (i < 0) return;
    final block = _blocks[i];
    if (block is ImageBlock) {
      try {
        File(block.path).deleteSync();
      } catch (_) {}
    }
    setState(() => _blocks.removeAt(i));
    _persistBlocks();
  }

  Future<void> _openStyleSheet(String noteId) async {
    final bloc = context.read<NoteEditorBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: NoteStyleSheet(noteId: noteId),
      ),
    );
  }

  Future<void> _openReminderSheet(String noteId) async {
    final bloc = context.read<NoteEditorBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: ReminderSheet(noteId: noteId),
      ),
    );
  }

  Future<void> _openTagSheet(String noteId) async {
    final bloc = context.read<NoteEditorBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: TagSheet(noteId: noteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NoteEditorBloc, NoteEditorState>(
      listenWhen: (prev, next) => next.popRequested && !prev.popRequested,
      listener: (ctx, state) => Navigator.of(ctx).pop(),
      builder: (ctx, state) {
        switch (state.status) {
          case NoteEditorStatus.notFound:
            return const _NotFoundScaffold();
          case NoteEditorStatus.error:
            return _ErrorScaffold(message: state.errorMessage ?? 'Editor error');
          case NoteEditorStatus.initial:
          case NoteEditorStatus.loading:
            return const _LoadingScaffold();
          case NoteEditorStatus.ready:
          case NoteEditorStatus.saving:
            final note = state.note;
            if (note == null) return const _LoadingScaffold();
            if (!_initialized) _initializeFromNote(note);
            return _buildBody(ctx, note);
        }
      },
    );
  }

  Widget _buildBody(BuildContext context, Note note) {
    final brightness = Theme.of(context).brightness;
    final swatch = NotesColorPalette.swatchFor(note.colorBackground);
    final activeBgColor = swatch?.background(brightness) ?? note.colorBackground;
    final autoTextColor = _computeTextColor(note, swatch, activeBgColor, brightness);
    final background = note.hasGradient && note.gradient != null ? null : activeBgColor;

    final currentBlock = _focusedBlockId == null
        ? (_blocks.isNotEmpty ? _blocks.first : null)
        : _blocks.firstWhere(
            (b) => b.id == _focusedBlockId,
            orElse: () => _blocks.first,
          );
    final currentIsChecklist = currentBlock is ChecklistBlock;

    return Scaffold(
      backgroundColor: background,
      extendBodyBehindAppBar: true,
      appBar: NoteAppBar(
        isPinned: note.isPinned,
        onTogglePin: () => context.read<NoteEditorBloc>().add(const PinToggled()),
        onDelete: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete note?'),
              content: const Text('This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            context.read<NoteEditorBloc>().add(const NoteDeleted());
          }
        },
        foregroundColor: autoTextColor,
      ),
      body: Container(
        decoration: note.hasGradient && note.gradient != null
            ? BoxDecoration(gradient: note.gradient)
            : note.patternImage != null
                ? BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(note.patternImage!),
                      fit: BoxFit.cover,
                      opacity: 0.5,
                      colorFilter: ColorFilter.mode(
                        activeBgColor,
                        BlendMode.softLight,
                      ),
                    ),
                  )
                : null,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  children: [
                    TextField(
                      controller: _titleController,
                      maxLength: 80,
                      onChanged: (text) => context.read<NoteEditorBloc>().add(TitleChanged(text)),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: autoTextColor,
                          ),
                      cursorColor: autoTextColor,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Title',
                        hintStyle: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: autoTextColor.withValues(alpha: 0.4),
                            ),
                      ),
                    ),
                    const Gap(AppSpacing.xs),
                    Text(
                      DateFormat('MMM d · HH:mm').format(note.dateCreated),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: autoTextColor.withValues(alpha: 0.6),
                          ),
                    ),
                    if (note.reminder != null) ...[
                      const Gap(AppSpacing.sm),
                      _ReminderChip(
                        date: note.reminder!,
                        textColor: autoTextColor,
                        onTap: () => _openReminderSheet(note.id),
                      ),
                    ],
                    if (note.tags.isNotEmpty) ...[
                      const Gap(AppSpacing.sm),
                      _TagsRow(tags: note.tags, textColor: autoTextColor),
                    ],
                    const Gap(AppSpacing.md),
                    ..._blocks.map((block) => _buildBlock(block, autoTextColor)),
                    const Gap(AppSpacing.xxxl),
                  ],
                ),
              ),
              EditorToolbar(
                currentBlockIsChecklist: currentIsChecklist,
                onToggleChecklist: _convertCurrentBlock,
                onAddImage: _addImage,
                onOpenStyleSheet: () => _openStyleSheet(note.id),
                onOpenReminderSheet: () => _openReminderSheet(note.id),
                onOpenTagSheet: () => _openTagSheet(note.id),
                onDoneEditing: () {
                  FocusScope.of(context).unfocus();
                  _persistBlocks();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _computeTextColor(
    Note note,
    NotesSwatch? swatch,
    Color activeBgColor,
    Brightness brightness,
  ) {
    if (note.hasGradient && note.gradient != null) {
      final avgLuminance = note.gradient!.colors.first.computeLuminance();
      return avgLuminance > 0.5 ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    }
    return swatch?.autoTextColor(brightness) ??
        (activeBgColor.computeLuminance() > 0.5
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF5F5F5));
  }

  Widget _buildBlock(EditorBlock block, Color? textColor) {
    return KeyedSubtree(
      key: ValueKey(block.id),
      child: switch (block) {
        TextBlock() => TextBlockWidget(
            block: block,
            focusNode: _focusFor(block.id),
            onChanged: (_) => _onBlockChanged(),
            onInsertBelow: (text) => _insertTextBlockBelow(block.id, text),
            onDeleteBlock: () => _deleteBlock(block.id),
            textColor: textColor,
          ),
        ChecklistBlock() => ChecklistBlockWidget(
            block: block,
            focusNode: _focusFor(block.id),
            onChanged: (_) => _onBlockChanged(),
            onCheckedChanged: (v) {
              setState(() => block.checked = v);
              _persistBlocks();
            },
            onInsertBelow: (text) => _insertChecklistBlockBelow(block.id, text),
            onConvertToText: () {
              final i = _blocks.indexWhere((b) => b.id == block.id);
              if (i < 0) return;
              final replacement = TextBlock(id: block.id, text: block.text);
              setState(() => _blocks[i] = replacement);
              _persistBlocks();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _focusBlock(replacement.id);
              });
            },
            textColor: textColor,
          ),
        ImageBlock() => ImageBlockWidget(
            path: block.path,
            onDelete: () => _deleteImageBlock(block.id),
          ),
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _NotFoundScaffold extends StatelessWidget {
  const _NotFoundScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Note not found.')),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(message)),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  final DateTime date;
  final Color? textColor;
  final VoidCallback onTap;
  const _ReminderChip({
    required this.date,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active_outlined, size: 14, color: color),
              const Gap(AppSpacing.xs),
              Text(
                DateFormat('MMM d · HH:mm').format(date),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  final Set<String> tags;
  final Color? textColor;
  const _TagsRow({required this.tags, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        separatorBuilder: (_, __) => const Gap(AppSpacing.xs),
        itemBuilder: (_, i) {
          final tag = tags.elementAt(i);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1.0),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$tag',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                  ),
            ),
          );
        },
      ),
    );
  }
}

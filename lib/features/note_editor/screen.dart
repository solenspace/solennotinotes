import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_cubit.dart';
import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/ai/llm_model_downloader.dart';
import 'package:noti_notes_app/services/ai/llm_runtime.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';
import 'package:noti_notes_app/services/speech/tts_service.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/tokens.dart';
import 'package:noti_notes_app/widgets/permissions/permission_explainer_sheet.dart';

import 'bloc/note_editor_bloc.dart';
import 'bloc/note_editor_event.dart';
import 'bloc/note_editor_state.dart';
import 'note_type.dart';
import 'widgets/ai_assist_button.dart';
import 'widgets/audio_block_view.dart';
import 'widgets/audio_capture_button.dart';
import 'widgets/checklist_block.dart';
import 'widgets/dictation_button.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/from_sender_chip.dart';
import 'widgets/image_block.dart';
import 'widgets/note_app_bar.dart';
import 'widgets/overlay_picker_sheet.dart';
import 'widgets/read_aloud_button.dart';
import 'widgets/read_aloud_overlay.dart';
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
    return MultiBlocProvider(
      providers: [
        BlocProvider<NoteEditorBloc>(
          create: (ctx) => NoteEditorBloc(
            repository: ctx.read<NotesRepository>(),
            identityRepository: ctx.read<NotiIdentityRepository>(),
            audio: ctx.read<AudioRepository>(),
            permissions: ctx.read<PermissionsService>(),
            stt: ctx.read<SttService>(),
            tts: ctx.read<TtsService>(),
          )..add(EditorOpened(noteId: noteId, noteType: noteType)),
        ),
        // Spec 20: per-route AI assist cubit. Lazy-loads the runtime on
        // first use (the screen may open hundreds of times without ever
        // touching AI), and `close()` calls `LlmRuntime.unload()` so the
        // worker isolate is freed when the editor route pops.
        BlocProvider<AiAssistCubit>(
          create: (ctx) => AiAssistCubit(
            runtime: ctx.read<LlmRuntime>(),
            modelPathResolver: () async {
              final file = await ctx.read<LlmModelDownloader>().resolveTargetFile();
              return file.path;
            },
          ),
        ),
      ],
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

  void _appendAudioBlock(AudioBlock block) {
    setState(() => _blocks.add(block));
    _persistBlocks();
  }

  /// Appends a dictated transcription to the active text block, or creates
  /// one when the last block is non-text or the editor is empty. Mirrors the
  /// audio-block commit flow: the bloc surfaces a one-shot string, the
  /// screen owns the actual block-list mutation, then [_persistBlocks]
  /// rounds the change back through `BlocksReplaced`.
  void _appendDictationText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_blocks.isEmpty) {
      setState(() => _blocks.add(newTextBlock(trimmed)));
    } else {
      final last = _blocks.last;
      if (last is TextBlock) {
        final separator = last.text.isEmpty ? '' : ' ';
        setState(() => last.text = '${last.text}$separator$trimmed');
      } else {
        setState(() => _blocks.add(newTextBlock(trimmed)));
      }
    }
    _persistBlocks();
  }

  void _deleteAudioBlock(String audioId) {
    final i = _blocks.indexWhere((b) => b is AudioBlock && b.id == audioId);
    if (i < 0) return;
    setState(() => _blocks.removeAt(i));
    _persistBlocks();
    context.read<NoteEditorBloc>().add(AudioBlockRemoved(audioId));
  }

  void _reRecordAudio(String audioId) {
    _deleteAudioBlock(audioId);
    context.read<NoteEditorBloc>().add(const AudioCaptureRequested());
  }

  void _showMicrophoneExplainer() {
    PermissionExplainerSheet.show(
      context,
      title: 'Microphone access needed',
      body: 'Notinotes records audio notes locally on your device. '
          'Enable microphone access in Settings to record voice notes.',
      result: PermissionResult.permanentlyDenied,
      service: context.read<PermissionsService>(),
    );
  }

  void _showDictationUnavailableExplainer() {
    PermissionExplainerSheet.show(
      context,
      title: 'Dictation unavailable',
      body: 'Speech recognition needs to run entirely on this device, but '
          'this device does not support offline recognition for your '
          'language. Notinotes will not use cloud recognition.',
      // No actual permission to repair: this is a capability hard-gate.
      // `restricted` surfaces a single "OK" path with no Settings button.
      result: PermissionResult.restricted,
      service: context.read<PermissionsService>(),
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
      listenWhen: (prev, next) {
        return (next.popRequested && !prev.popRequested) ||
            (next.committedAudioBlock != null) ||
            (next.audioPermissionExplainerRequested && !prev.audioPermissionExplainerRequested) ||
            (next.committedDictationText != null) ||
            (next.dictationUnavailableExplainerRequested &&
                !prev.dictationUnavailableExplainerRequested) ||
            (next.errorMessage != null && next.errorMessage != prev.errorMessage);
      },
      listener: (ctx, state) {
        if (state.popRequested) {
          Navigator.of(ctx).pop();
          return;
        }
        if (state.audioPermissionExplainerRequested) {
          _showMicrophoneExplainer();
        }
        if (state.dictationUnavailableExplainerRequested) {
          _showDictationUnavailableExplainer();
        }
        final committedAudio = state.committedAudioBlock;
        if (committedAudio != null) {
          _appendAudioBlock(committedAudio);
        }
        final committedText = state.committedDictationText;
        if (committedText != null) {
          _appendDictationText(committedText);
        }
        final err = state.errorMessage;
        if (err != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err)));
        }
      },
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
    final base = Theme.of(context);
    final baseTokens = context.tokens;
    final overlay = note.toOverlay();
    final patchedColors = overlay.applyToColors(baseTokens.colors);
    final patchedPattern = overlay.applyToPatternBackdrop(baseTokens.patternBackdrop);
    final patchedSignature = overlay.applyToSignature(baseTokens.signature);

    final themed = base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        patchedColors,
        baseTokens.text,
        baseTokens.motion,
        baseTokens.shape,
        baseTokens.elevation,
        baseTokens.spacing,
        patchedPattern,
        patchedSignature,
      ],
    );

    final currentBlock = _focusedBlockId == null
        ? (_blocks.isNotEmpty ? _blocks.first : null)
        : _blocks.firstWhere(
            (b) => b.id == _focusedBlockId,
            orElse: () => _blocks.first,
          );
    final currentIsChecklist = currentBlock is ChecklistBlock;
    final showFromSenderChip = overlay.fromIdentityId != null;
    final isDarkSurface = patchedColors.surface.computeLuminance() < 0.5;

    return AnimatedTheme(
      data: themed,
      duration: baseTokens.motion.pattern,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: patchedColors.surface,
          statusBarIconBrightness: isDarkSurface ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDarkSurface ? Brightness.dark : Brightness.light,
        ),
        child: Builder(
          builder: (themedCtx) {
            final tokens = themedCtx.tokens;
            return Scaffold(
              backgroundColor: tokens.colors.surface,
              extendBodyBehindAppBar: true,
              appBar: NoteAppBar(
                isPinned: note.isPinned,
                backgroundColor: tokens.colors.surfaceVariant,
                foregroundColor: tokens.colors.onSurface,
                title: showFromSenderChip ? const FromSenderChip() : null,
                onTogglePin: () => themedCtx.read<NoteEditorBloc>().add(const PinToggled()),
                onDelete: () async {
                  final confirmed = await showDialog<bool>(
                    context: themedCtx,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete note?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(themedCtx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(themedCtx).pop(true),
                          child: Text(
                            'Delete',
                            style: TextStyle(color: tokens.colors.error),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && themedCtx.mounted) {
                    themedCtx.read<NoteEditorBloc>().add(const NoteDeleted());
                  }
                },
              ),
              body: _PatternedBackdrop(
                patternKey: NotiPatternKey.fromString(patchedPattern.patternKey),
                bodyOpacity: patchedPattern.bodyOpacity,
                headerOpacity: patchedPattern.headerOpacity,
                headerHeightFraction: patchedPattern.headerHeightFraction,
                child: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacing.lg,
                            vertical: tokens.spacing.md,
                          ),
                          children: [
                            TextField(
                              controller: _titleController,
                              maxLength: 80,
                              onChanged: (text) =>
                                  themedCtx.read<NoteEditorBloc>().add(TitleChanged(text)),
                              style: tokens.text.displayLg.copyWith(
                                color: tokens.colors.onSurface,
                              ),
                              cursorColor: tokens.colors.onSurface,
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Title',
                                hintStyle: tokens.text.displayLg.copyWith(
                                  color: tokens.colors.onSurface.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            Gap(tokens.spacing.xs),
                            Text(
                              DateFormat('MMM d · HH:mm').format(note.dateCreated),
                              style: tokens.text.labelSm.copyWith(
                                color: tokens.colors.onSurfaceMuted,
                              ),
                            ),
                            if (note.reminder != null) ...[
                              Gap(tokens.spacing.sm),
                              _ReminderChip(
                                date: note.reminder!,
                                textColor: tokens.colors.onSurface,
                                onTap: () => _openReminderSheet(note.id),
                              ),
                            ],
                            if (note.tags.isNotEmpty) ...[
                              Gap(tokens.spacing.sm),
                              _TagsRow(
                                tags: note.tags,
                                textColor: tokens.colors.onSurface,
                              ),
                            ],
                            Gap(tokens.spacing.md),
                            ..._blocks.asMap().entries.map(
                                  (entry) => _buildBlock(
                                    entry.value,
                                    tokens.colors.onSurface,
                                    blockIndex: entry.key,
                                  ),
                                ),
                            Gap(tokens.spacing.xxxl),
                          ],
                        ),
                      ),
                      const ReadAloudOverlay(),
                      const _DictationDraftBanner(),
                      EditorToolbar(
                        currentBlockIsChecklist: currentIsChecklist,
                        onToggleChecklist: _convertCurrentBlock,
                        onAddImage: _addImage,
                        onOpenStyleSheet: () => OverlayPickerSheet.show(themedCtx),
                        onResetOverlay: () => themedCtx
                            .read<NoteEditorBloc>()
                            .add(const OverlayResetToIdentityDefault()),
                        onOpenReminderSheet: () => _openReminderSheet(note.id),
                        onOpenTagSheet: () => _openTagSheet(note.id),
                        onDoneEditing: () {
                          FocusScope.of(themedCtx).unfocus();
                          _persistBlocks();
                        },
                        audioCaptureButton: const AudioCaptureButton(),
                        dictationButton: const DictationButton(),
                        readAloudButton: const ReadAloudButton(),
                        assistButton: const AiAssistButton(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBlock(EditorBlock block, Color? textColor, {required int blockIndex}) {
    return KeyedSubtree(
      key: ValueKey(block.id),
      child: switch (block) {
        TextBlock() => TextBlockWidget(
            block: block,
            focusNode: _focusFor(block.id),
            onChanged: (_) => _onBlockChanged(),
            onInsertBelow: (text) => _insertTextBlockBelow(block.id, text),
            onDeleteBlock: () => _deleteBlock(block.id),
            onReadAloud: () =>
                context.read<NoteEditorBloc>().add(ReadAloudRequested(blockIndex: blockIndex)),
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
            onReadAloud: () =>
                context.read<NoteEditorBloc>().add(ReadAloudRequested(blockIndex: blockIndex)),
            textColor: textColor,
          ),
        ImageBlock() => ImageBlockWidget(
            path: block.path,
            onDelete: () => _deleteImageBlock(block.id),
          ),
        AudioBlock() => AudioBlockView(
            block: block,
            onDelete: () => _deleteAudioBlock(block.id),
            onReRecord: () => _reRecordAudio(block.id),
          ),
      },
    );
  }
}

/// In-flight dictation feedback pinned above the toolbar. Renders the
/// recognizer's growing partial transcription as muted italic text so the
/// user has immediate "we hear you" confirmation. Hidden when not dictating.
class _DictationDraftBanner extends StatelessWidget {
  const _DictationDraftBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.isDictating != b.isDictating || a.dictationDraft != b.dictationDraft,
      builder: (ctx, state) {
        if (!state.isDictating) return const SizedBox.shrink();
        final tokens = ctx.tokens;
        final draft = state.dictationDraft;
        final preview = (draft == null || draft.isEmpty) ? 'Listening…' : draft;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.xs,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.colors.surfaceVariant.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              border: Border.all(
                color: tokens.colors.accent.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over_rounded,
                  size: 16,
                  color: tokens.colors.accent,
                ),
                Gap(tokens.spacing.xs),
                Expanded(
                  child: Text(
                    preview,
                    style: tokens.text.bodySm.copyWith(
                      color: tokens.colors.onSurfaceMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
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
            horizontal: SpacingPrimitives.md,
            vertical: SpacingPrimitives.xs + 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active_outlined, size: 14, color: color),
              const Gap(SpacingPrimitives.xs),
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
        separatorBuilder: (_, __) => const Gap(SpacingPrimitives.xs),
        itemBuilder: (_, i) {
          final tag = tags.elementAt(i);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: SpacingPrimitives.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
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

/// Two-zone pattern renderer: full opacity in the top
/// [headerHeightFraction] of the canvas, body opacity below, with a 16px
/// linear feather between the two zones. Patterns are picked from the
/// bundled [NotiPatternKey] PNG set; null disables the pattern entirely.
class _PatternedBackdrop extends StatelessWidget {
  const _PatternedBackdrop({
    required this.patternKey,
    required this.bodyOpacity,
    required this.headerOpacity,
    required this.headerHeightFraction,
    required this.child,
  });

  final NotiPatternKey? patternKey;
  final double bodyOpacity;
  final double headerOpacity;
  final double headerHeightFraction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (patternKey == null || (bodyOpacity == 0 && headerOpacity == 0)) {
      return child;
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: headerOpacity),
                Colors.black.withValues(alpha: headerOpacity),
                Colors.black.withValues(alpha: bodyOpacity),
                Colors.black.withValues(alpha: bodyOpacity),
              ],
              stops: [
                0.0,
                (headerHeightFraction - 0.04).clamp(0.0, 1.0),
                (headerHeightFraction + 0.04).clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Image.asset(
              patternKey!.assetPath,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

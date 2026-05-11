import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_cubit.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_listener_service.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_state.dart';
import 'package:noti_notes_app/features/inbox/widgets/inbox_row.dart';
import 'package:noti_notes_app/features/inbox/widgets/share_preview_panel.dart';
import 'package:noti_notes_app/features/note_editor/screen.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/crypto/keypair_service.dart';
import 'package:noti_notes_app/theme/tokens.dart';
import 'package:path_provider/path_provider.dart';

/// Receiver-side screen for nearby shares (Spec 25). Shows pending
/// entries from [ReceivedInboxRepository], lets the user toggle the
/// opt-in receive transport, and routes to a full-screen
/// [SharePreviewPanel] for accept/discard.
class InboxScreen extends StatelessWidget {
  static const routeName = '/inbox';

  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<InboxCubit>(
      create: (ctx) {
        final identityCubit = ctx.read<NotiIdentityCubit>();
        NotiIdentity readIdentity() {
          final value = identityCubit.state.identity;
          if (value == null) {
            throw StateError('NotiIdentity not loaded before opening the inbox.');
          }
          return value;
        }

        final listener = InboxListenerService(
          peer: ctx.read<PeerService>(),
          decoder: ShareDecoder(
            keypair: ctx.read<KeypairService>(),
            documentsRoot: _SyncDocumentsRoot.cached,
          ),
          inbox: ctx.read<ReceivedInboxRepository>(),
          identity: readIdentity,
        );
        return InboxCubit(
          repository: ctx.read<ReceivedInboxRepository>(),
          listener: listener,
        )..start();
      },
      child: const _InboxView(),
    );
  }
}

/// Lazy holder for `getApplicationDocumentsDirectory()` so the inbox
/// route can construct a [ShareDecoder] synchronously inside
/// `BlocProvider.create`. Resolved once at app start by `main.dart`
/// before the home screen mounts; the screen never blocks on the
/// platform channel here.
class _SyncDocumentsRoot {
  static Directory? _cached;
  static Directory get cached {
    final value = _cached;
    if (value == null) {
      throw StateError(
        'InboxScreen._SyncDocumentsRoot.cached read before _SyncDocumentsRoot.prime() resolved.',
      );
    }
    return value;
  }

  /// Idempotent. Called from `main()` so `InboxScreen` can build
  /// `ShareDecoder` without an async hop in its widget tree.
  static Future<void> prime() async {
    _cached ??= await getApplicationDocumentsDirectory();
  }
}

/// Public entry point so `main.dart` can wait for the documents root
/// to resolve before `runApp`.
Future<void> primeInboxDocumentsRoot() => _SyncDocumentsRoot.prime();

class _InboxView extends StatefulWidget {
  const _InboxView();

  @override
  State<_InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<_InboxView> {
  StreamSubscription<InboxListenerEvent>? _eventsSub;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<InboxCubit>();
    _eventsSub = cubit.uiEvents.listen(_onListenerEvent);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  void _onListenerEvent(InboxListenerEvent event) {
    if (!mounted) return;
    final text = switch (event) {
      DecodeRejected() => context.l10n.inbox_unreadable_share,
      PeerStartFailed() => context.l10n.inbox_receive_start_failed,
      ShareReceived() => null,
    };
    if (text == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.inbox_title)),
      body: BlocBuilder<InboxCubit, InboxState>(
        builder: (ctx, state) {
          return Column(
            children: [
              _ReceiveToggle(status: state.listener),
              const Divider(height: 1),
              Expanded(
                child: state.entries.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
                        itemCount: state.entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final share = state.entries[i];
                          return InboxRow(
                            share: share,
                            onTap: () => _openPreview(ctx, share),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPreview(BuildContext rowContext, ReceivedShare share) async {
    final cubit = rowContext.read<InboxCubit>();
    final navigator = Navigator.of(rowContext);
    final messenger = ScaffoldMessenger.of(rowContext);
    final outcome = await navigator.push<_PreviewOutcome>(
      MaterialPageRoute<_PreviewOutcome>(
        builder: (_) => _PreviewRoute(share: share),
      ),
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case _PreviewOutcome.accept:
        try {
          final note = await cubit.accept(share.shareId);
          if (!mounted) return;
          await navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => NoteEditorScreen(noteId: note.id),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(context.l10n.inbox_accept_failed(e.toString())),
            ),
          );
        }
      case _PreviewOutcome.discard:
        await cubit.discard(share.shareId);
    }
  }
}

class _ReceiveToggle extends StatelessWidget {
  const _ReceiveToggle({required this.status});

  final InboxListenerStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final isOn = status == InboxListenerStatus.on;
    final isStarting = status == InboxListenerStatus.starting;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Row(
        children: [
          Icon(
            isOn ? Icons.bluetooth_searching_rounded : Icons.bluetooth_disabled_rounded,
            color: isOn ? tokens.colors.accent : scheme.onSurfaceVariant,
          ),
          Gap(tokens.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.inbox_receive_title, style: tokens.text.titleSm),
                Gap(tokens.spacing.xs),
                Text(
                  _subtitleFor(context, status),
                  style: tokens.text.bodySm.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Gap(tokens.spacing.md),
          if (isStarting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: isOn,
              onChanged: (value) {
                final cubit = context.read<InboxCubit>();
                if (value) {
                  cubit.startReceiving();
                } else {
                  cubit.stopReceiving();
                }
              },
            ),
        ],
      ),
    );
  }

  String _subtitleFor(BuildContext context, InboxListenerStatus status) => switch (status) {
        InboxListenerStatus.off => context.l10n.inbox_receive_off,
        InboxListenerStatus.starting => context.l10n.inbox_receive_starting,
        InboxListenerStatus.on => context.l10n.inbox_receive_on,
        InboxListenerStatus.failed => context.l10n.inbox_receive_failed,
      };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: scheme.onSurfaceVariant),
            Gap(tokens.spacing.md),
            Text(context.l10n.inbox_empty_title, style: tokens.text.titleMd),
            Gap(tokens.spacing.xs),
            Text(
              context.l10n.inbox_empty_description,
              style: tokens.text.bodyMd.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _PreviewOutcome { accept, discard }

class _PreviewRoute extends StatelessWidget {
  const _PreviewRoute({required this.share});

  final ReceivedShare share;

  @override
  Widget build(BuildContext context) {
    return SharePreviewPanel(
      share: share,
      onAccept: () => Navigator.of(context).pop(_PreviewOutcome.accept),
      onDiscard: () => Navigator.of(context).pop(_PreviewOutcome.discard),
    );
  }
}

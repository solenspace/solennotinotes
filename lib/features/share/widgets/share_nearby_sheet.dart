import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/share/cubit/share_nearby_cubit.dart';
import 'package:noti_notes_app/features/share/cubit/share_nearby_state.dart';
import 'package:noti_notes_app/features/share/widgets/peer_card.dart';
import 'package:noti_notes_app/features/share/widgets/transfer_progress_panel.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/services/crypto/keypair_service.dart';
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/theme/tokens.dart';
import 'package:noti_notes_app/widgets/permissions/permission_explainer_sheet.dart';

/// Sender-side share sheet (Spec 24). Three phases inside one
/// `DraggableScrollableSheet`: discover → sending → completed/failed.
/// Chrome reflects the source note's overlay so the act of sharing
/// visually carries the note's identity (App Style, Spec 11).
class ShareNearbySheet extends StatelessWidget {
  const ShareNearbySheet._({required this.themed});

  final ThemeData themed;

  static Future<void> show(BuildContext context, {required List<Note> notes}) async {
    if (notes.isEmpty) return;

    final permissions = context.read<PermissionsService>();
    final allowed = await _ensureBluetoothPermissions(context, permissions);
    if (!allowed || !context.mounted) return;

    final peer = context.read<PeerService>();
    final keypair = context.read<KeypairService>();
    final identityCubit = context.read<NotiIdentityCubit>();
    final encoder = ShareEncoder(keypair: keypair);

    final themed = _buildAppStyleTheme(context, notes.first);

    ShareNearbyCubit? cubit;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: themed.extension<NotiColors>()!.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(themed.extension<NotiShape>()!.lg),
        ),
      ),
      builder: (_) => BlocProvider<ShareNearbyCubit>(
        create: (_) {
          final c = ShareNearbyCubit(
            peerService: peer,
            encoder: encoder,
            identity: () {
              final id = identityCubit.state.identity;
              if (id == null) {
                throw StateError('NotiIdentity not loaded; share opened too early.');
              }
              return id;
            },
          );
          cubit = c;
          unawaited(c.open(notes));
          return c;
        },
        child: ShareNearbySheet._(themed: themed),
      ),
    );

    await cubit?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themed,
      child: Builder(
        builder: (themedCtx) {
          final tokens = themedCtx.tokens;
          return DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, scroll) => Column(
              children: [
                const _DragHandle(),
                Expanded(
                  child: BlocBuilder<ShareNearbyCubit, ShareNearbyState>(
                    builder: (_, state) => _Body(state: state, scroll: scroll),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.spacing.lg,
                    tokens.spacing.sm,
                    tokens.spacing.lg,
                    tokens.spacing.md,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth_rounded,
                        size: 14,
                        color: tokens.colors.onSurfaceMuted,
                      ),
                      Gap(tokens.spacing.xs),
                      Expanded(
                        child: Text(
                          'Sent over Bluetooth — never through the internet.',
                          style: tokens.text.labelSm.copyWith(
                            color: tokens.colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.scroll});

  final ShareNearbyState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case ShareNearbyPhase.discovering:
        return _DiscoverBody(state: state, scroll: scroll);
      case ShareNearbyPhase.sending:
        return TransferProgressPanel(
          state: state,
          onCancel: () => context.read<ShareNearbyCubit>().cancel(),
        );
      case ShareNearbyPhase.completed:
        return const _CompletedBody();
      case ShareNearbyPhase.failed:
        return _FailedBody(state: state);
    }
  }
}

class _DiscoverBody extends StatelessWidget {
  const _DiscoverBody({required this.state, required this.scroll});

  final ShareNearbyState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final peers = state.peers;
    return ListView(
      controller: scroll,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      children: [
        Text(
          'Looking for nearby people…',
          style: tokens.text.headlineMd.copyWith(color: colors.onSurface),
        ),
        Gap(tokens.spacing.xs),
        Text(
          state.queue.length > 1
              ? '${state.queue.length} notes ready to send.'
              : 'Pick someone to send to.',
          style: tokens.text.bodyMd.copyWith(color: colors.onSurfaceMuted),
        ),
        Gap(tokens.spacing.lg),
        if (peers.isEmpty)
          _EmptyDiscoveryHint(spacing: tokens.spacing.md, colors: colors, text: tokens.text)
        else
          for (var i = 0; i < peers.length; i++) ...[
            if (i > 0) Gap(tokens.spacing.sm),
            PeerCard(
              peer: peers[i],
              onTap: () => context.read<ShareNearbyCubit>().sendTo(peers[i]),
            ),
          ],
      ],
    );
  }
}

class _EmptyDiscoveryHint extends StatelessWidget {
  const _EmptyDiscoveryHint({
    required this.spacing,
    required this.colors,
    required this.text,
  });

  final double spacing;
  final NotiColors colors;
  final NotiText text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Searching for nearby people. Make sure their app is open and Bluetooth is on.',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            Gap(spacing),
            Expanded(
              child: Text(
                'Make sure their app is open and Bluetooth is on.',
                style: text.bodyMd.copyWith(color: colors.onSurfaceMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedBody extends StatefulWidget {
  const _CompletedBody();

  @override
  State<_CompletedBody> createState() => _CompletedBodyState();
}

class _CompletedBodyState extends State<_CompletedBody> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    final accessible = MediaQuery.of(context).accessibleNavigation;
    if (!accessible) {
      _autoDismiss = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final notesSent = context.read<ShareNearbyCubit>().state.queue.length;
    final label = notesSent > 1 ? 'Sent $notesSent notes.' : 'Sent.';
    return Semantics(
      liveRegion: true,
      label: label,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: colors.success),
            Gap(tokens.spacing.md),
            Text(
              label,
              style: tokens.text.headlineMd.copyWith(color: colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.state});

  final ShareNearbyState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final copy = _failureCopy(state.failure);
    return Padding(
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: colors.error),
              Gap(tokens.spacing.sm),
              Expanded(
                child: Text(
                  copy.title,
                  style: tokens.text.headlineMd.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
          Gap(tokens.spacing.sm),
          Text(
            copy.body,
            style: tokens.text.bodyMd.copyWith(color: colors.onSurfaceMuted),
          ),
          Gap(tokens.spacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureCopy {
  const _FailureCopy(this.title, this.body);
  final String title;
  final String body;
}

_FailureCopy _failureCopy(ShareNearbyFailure? failure) {
  switch (failure) {
    case ShareNearbyFailure.permissionStartFailed:
      return const _FailureCopy(
        "Couldn't start sharing",
        'Bluetooth or Nearby permissions are unavailable on this device.',
      );
    case ShareNearbyFailure.payloadTooLarge:
      return const _FailureCopy(
        'Note too large to share',
        'Try removing audio or large images and send again.',
      );
    case ShareNearbyFailure.encodeError:
      return const _FailureCopy(
        "Couldn't prepare the note",
        'Something went wrong packaging this note. Try again.',
      );
    case ShareNearbyFailure.transferCancelled:
      return const _FailureCopy(
        'Sending cancelled',
        'No data was sent.',
      );
    case ShareNearbyFailure.transferFailed:
      return const _FailureCopy(
        "Couldn't send",
        'The connection dropped before the note finished sending.',
      );
    case null:
      return const _FailureCopy(
        "Couldn't send",
        'Something went wrong. Try again.',
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

ThemeData _buildAppStyleTheme(BuildContext context, Note source) {
  final base = Theme.of(context);
  final baseTokens = context.tokens;
  final overlay = source.toOverlay();
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      overlay.applyToColors(baseTokens.colors),
      baseTokens.text,
      baseTokens.motion,
      baseTokens.shape,
      baseTokens.elevation,
      baseTokens.spacing,
      overlay.applyToPatternBackdrop(baseTokens.patternBackdrop),
      overlay.applyToSignature(baseTokens.signature),
    ],
  );
}

/// Sequentially requests the three Bluetooth permissions the share
/// transport needs. On the first non-granted result, surfaces the
/// shared explainer sheet (Spec 12) — including the "Open settings"
/// CTA when the OS has put the request out of reach — and returns
/// false so the caller skips opening the share sheet.
Future<bool> _ensureBluetoothPermissions(
  BuildContext context,
  PermissionsService service,
) async {
  final requests = <Future<PermissionResult> Function()>[
    service.requestBluetoothScan,
    service.requestBluetoothConnect,
    service.requestBluetoothAdvertise,
  ];
  for (final request in requests) {
    final result = await request();
    if (result.isUsable) continue;
    if (!context.mounted) return false;
    await PermissionExplainerSheet.show(
      context,
      title: 'Nearby sharing needs Bluetooth',
      body:
          'Noti uses Bluetooth to find devices near you and send notes directly. Nothing leaves your device over the internet.',
      result: result,
      service: service,
    );
    return false;
  }
  return true;
}

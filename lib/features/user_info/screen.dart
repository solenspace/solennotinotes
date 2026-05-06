import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';

import 'package:noti_notes_app/features/home/bloc/notes_list_bloc.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';

import 'cubit/noti_identity_cubit.dart';

class UserInfoScreen extends StatelessWidget {
  static const routeName = '/user-info';
  const UserInfoScreen({super.key});

  Future<void> _pickProfileImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await const ImagePickerService().pickImage(source, 80);
    if (file != null && context.mounted) {
      await context.read<NotiIdentityCubit>().updatePhoto(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<NotiIdentityCubit>().state.identity;
    final notesState = context.watch<NotesListBloc>().state;
    final scheme = Theme.of(context).colorScheme;
    final mostUsed = _topFiveTags(notesState.notes);

    if (identity == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingPrimitives.lg,
          vertical: SpacingPrimitives.md,
        ),
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _pickProfileImage(context),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                    border: Border.all(color: scheme.outline, width: 1.0),
                    image: identity.profilePicture != null
                        ? DecorationImage(
                            image: FileImage(File(identity.profilePicture!.path)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: identity.profilePicture == null
                      ? Icon(
                          Icons.person_outline,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
              const Gap(SpacingPrimitives.lg),
              Expanded(
                child: TextFormField(
                  initialValue: identity.displayName,
                  maxLength: 30,
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'Your name',
                  ),
                  onChanged: (name) => context.read<NotiIdentityCubit>().updateDisplayName(name),
                ),
              ),
            ],
          ),
          const Gap(SpacingPrimitives.xl),
          Text(
            '${notesState.notes.length} notes on this device',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Gap(SpacingPrimitives.xl),
          // Spec 09 plumbing: minimal controls so the data layer is
          // exercisable end-to-end. Spec 11 (noti-theme-overlay) replaces
          // these with the proper signature editor.
          _SignaturePlumbing(identity: identity),
          const Gap(SpacingPrimitives.xl),
          Text(
            'TAGS YOU USE THE MOST',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const Gap(SpacingPrimitives.sm),
          if (mostUsed.isEmpty)
            Text(
              'No tags yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            )
          else
            Wrap(
              spacing: SpacingPrimitives.sm,
              runSpacing: SpacingPrimitives.sm,
              children: mostUsed
                  .map(
                    (t) => Chip(
                      label: Text('#$t'),
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _SignaturePlumbing extends StatelessWidget {
  const _SignaturePlumbing({required this.identity});

  final NotiIdentity identity;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NotiIdentityCubit>();
    final scheme = Theme.of(context).colorScheme;
    final sectionLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: scheme.onSurfaceVariant,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SIGNATURE PALETTE', style: sectionLabelStyle),
        const Gap(SpacingPrimitives.sm),
        Wrap(
          spacing: SpacingPrimitives.sm,
          runSpacing: SpacingPrimitives.sm,
          children: NotiIdentityDefaults.starterPalettes.map((palette) {
            final selected = _palettesEqual(identity.signaturePalette, palette);
            return GestureDetector(
              onTap: () => cubit.updatePalette(palette),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: palette
                      .map(
                        (c) => Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(RadiusPrimitives.xs),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            );
          }).toList(),
        ),
        const Gap(SpacingPrimitives.lg),
        Text('SIGNATURE PATTERN', style: sectionLabelStyle),
        const Gap(SpacingPrimitives.sm),
        DropdownButton<String?>(
          value: NotiPatternKey.fromString(identity.signaturePatternKey)?.name,
          isExpanded: true,
          hint: const Text('No pattern'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No pattern'),
            ),
            ...NotiPatternKey.values.map(
              (p) => DropdownMenuItem<String?>(
                value: p.name,
                child: Text(p.name),
              ),
            ),
          ],
          onChanged: cubit.updatePatternKey,
        ),
        const Gap(SpacingPrimitives.lg),
        Text('SIGNATURE ACCENT', style: sectionLabelStyle),
        const Gap(SpacingPrimitives.sm),
        TextFormField(
          initialValue: identity.signatureAccent ?? '',
          maxLength: 8, // grapheme-counted in cubit; allow combining marks
          decoration: const InputDecoration(
            counterText: '',
            hintText: 'Single character',
          ),
          onChanged: (value) async {
            try {
              await cubit.updateAccent(value);
            } on ArgumentError {
              // Multi-grapheme — silently rejected at this stage; Spec 11
              // wires real validation feedback into the UI.
            }
          },
        ),
        const Gap(SpacingPrimitives.lg),
        Text('SIGNATURE TAGLINE', style: sectionLabelStyle),
        const Gap(SpacingPrimitives.sm),
        TextFormField(
          initialValue: identity.signatureTagline,
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'A short line shown on shared notes',
          ),
          onChanged: cubit.updateTagline,
        ),
      ],
    );
  }

  static bool _palettesEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }
}

Set<String> _topFiveTags(List<Note> notes) {
  final counts = <String, int>{};
  for (final note in notes) {
    for (final tag in note.tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) => e.key).toSet();
}

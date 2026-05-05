import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';

import 'package:noti_notes_app/features/home/legacy/notes_provider.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/theme/app_tokens.dart';

import 'cubit/user_cubit.dart';

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
      await context.read<UserCubit>().updatePhoto(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserCubit>().state.user;
    final notes = context.watch<Notes>();
    final scheme = Theme.of(context).colorScheme;
    final mostUsed = notes.getMostUsedTags();

    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
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
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: scheme.outline, width: 1.0),
                    image: user.profilePicture != null
                        ? DecorationImage(
                            image: FileImage(File(user.profilePicture!.path)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: user.profilePicture == null
                      ? Icon(
                          Icons.person_outline,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
              const Gap(AppSpacing.lg),
              Expanded(
                child: TextFormField(
                  initialValue: user.name,
                  maxLength: 30,
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'Your name',
                  ),
                  onChanged: (name) => context.read<UserCubit>().updateName(name),
                ),
              ),
            ],
          ),
          const Gap(AppSpacing.xl),
          Text(
            '${notes.notesCount} notes on this device',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Gap(AppSpacing.xl),
          Text(
            'TAGS YOU USE THE MOST',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const Gap(AppSpacing.sm),
          if (mostUsed.isEmpty)
            Text(
              'No tags yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/search/cubit/search_cubit.dart';
import 'package:noti_notes_app/features/search/cubit/search_state.dart';
import 'package:noti_notes_app/theme/app_tokens.dart';

/// Horizontal row of filter chips below the search bar. Selection is single.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchCubit>().state;
    final entries = const [
      (NoteFilter.all, 'All', Icons.notes_outlined),
      (NoteFilter.reminders, 'Reminders', Icons.notifications_outlined),
      (NoteFilter.checklists, 'Checklists', Icons.checklist_rounded),
      (NoteFilter.images, 'Images', Icons.image_outlined),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Gap(AppSpacing.sm),
        itemBuilder: (_, i) {
          final (filter, label, icon) = entries[i];
          final selected = search.filter == filter;

          final colorScheme = Theme.of(context).colorScheme;
          final textColor = selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

          return FilterChip(
            avatar: Icon(icon, size: 16, color: textColor),
            label: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            selected: selected,
            onSelected: (_) => context.read<SearchCubit>().setFilter(filter),
            showCheckmark: false,
            backgroundColor: colorScheme.surfaceContainerHighest,
            selectedColor: colorScheme.primary,
          );
        },
      ),
    );
  }
}

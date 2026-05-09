import 'package:board_datetime_picker/board_datetime_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/notification_id.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';
import 'package:noti_notes_app/widgets/sheets/sheet_scaffold.dart';

/// Quick chips for common reminders + an inline date/time picker for the
/// "Pick date & time" branch. Replaces the old duration-wheel UI.
class ReminderSheet extends StatefulWidget {
  final String noteId;
  const ReminderSheet({super.key, required this.noteId});

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  bool _showPicker = false;
  DateTime _pendingDate = DateTime.now().add(const Duration(hours: 1));
  final BoardDateTimeController _controller = BoardDateTimeController();

  Future<void> _ensurePermission(PermissionsService service) async {
    final status = await service.notificationsStatus();
    if (status.isUsable) return;
    await service.requestNotifications();
  }

  Future<void> _setReminder(DateTime date) async {
    if (date.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a future time')),
      );
      return;
    }
    await _ensurePermission(context.read<PermissionsService>());
    if (!mounted) return;

    final bloc = context.read<NoteEditorBloc>();
    final note = bloc.state.note;
    if (note == null) return;

    bloc.add(ReminderSet(date));

    final body = note.title.isEmpty ? 'a note' : note.title;
    final service = LocalNotificationService();
    service.addNotification(
      notificationIdForNote(note.id),
      service.notificationMessage(body, ''),
      body,
      date,
      note.id,
      channel: 'reminders',
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _cancelReminder() {
    final bloc = context.read<NoteEditorBloc>();
    final note = bloc.state.note;
    if (note == null) return;
    bloc.add(const ReminderRemoved());
    LocalNotificationService.cancelNotification(notificationIdForNote(note.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      builder: (context, state) {
        final hasReminder = state.note?.reminder != null;
        return SheetScaffold(
          title: 'Remind me',
          child: AnimatedSize(
            duration: DurationPrimitives.standard,
            curve: CurvePrimitives.calm,
            alignment: Alignment.topCenter,
            child: _showPicker ? _buildPicker(context) : _buildChips(context, hasReminder),
          ),
        );
      },
    );
  }

  Widget _buildChips(BuildContext context, bool hasReminder) {
    final now = DateTime.now();
    final laterToday = DateTime(now.year, now.month, now.day, 18);
    final tomorrow = DateTime(now.year, now.month, now.day, 9).add(const Duration(days: 1));
    final saturday = _nextWeekday(DateTime.monday + 5, 9);
    final nextMonday = _nextWeekday(DateTime.monday, 9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: SpacingPrimitives.sm,
          runSpacing: SpacingPrimitives.sm,
          children: [
            if (laterToday.isAfter(now))
              _Chip(
                label: 'Later today',
                sublabel: DateFormat('HH:mm').format(laterToday),
                onTap: () => _setReminder(laterToday),
              ),
            _Chip(
              label: 'Tomorrow morning',
              sublabel: DateFormat('EEE HH:mm').format(tomorrow),
              onTap: () => _setReminder(tomorrow),
            ),
            _Chip(
              label: 'This weekend',
              sublabel: DateFormat('EEE HH:mm').format(saturday),
              onTap: () => _setReminder(saturday),
            ),
            _Chip(
              label: 'Next week',
              sublabel: DateFormat('EEE HH:mm').format(nextMonday),
              onTap: () => _setReminder(nextMonday),
            ),
            _Chip(
              label: 'Pick date & time',
              icon: Icons.calendar_month_outlined,
              onTap: () => setState(() => _showPicker = true),
            ),
          ],
        ),
        if (hasReminder) ...[
          const Gap(SpacingPrimitives.lg),
          TextButton.icon(
            onPressed: _cancelReminder,
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('Cancel reminder'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ],
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          child: BoardDateTimeBuilder(
            controller: _controller,
            pickerType: DateTimePickerType.datetime,
            initialDate: _pendingDate,
            minimumDate: DateTime.now(),
            options: const BoardDateTimeOptions(
              languages: BoardPickerLanguages.en(),
            ),
            builder: (context) => const SizedBox.shrink(),
            onChange: (date) => _pendingDate = date,
          ),
        ),
        const Gap(SpacingPrimitives.md),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _showPicker = false),
              child: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _setReminder(_pendingDate),
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Set reminder'),
            ),
          ],
        ),
      ],
    );
  }

  /// Returns the next occurrence of the given weekday (Monday=1..Sunday=7)
  /// at the given hour, in the future.
  DateTime _nextWeekday(int weekday, int hour) {
    final now = DateTime.now();
    int daysAhead = (weekday - now.weekday) % 7;
    if (daysAhead == 0) daysAhead = 7;
    final target = DateTime(now.year, now.month, now.day, hour).add(Duration(days: daysAhead));
    return target;
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? sublabel;
  final IconData? icon;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    this.sublabel,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingPrimitives.lg,
            vertical: SpacingPrimitives.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.primary),
                const Gap(SpacingPrimitives.sm),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

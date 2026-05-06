import 'package:flutter/material.dart';

import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Modal bottom sheet that explains why a permission is needed and — when
/// the OS has put the request out of reach (`permanentlyDenied` /
/// `restricted`) — links the user to the app-settings panel via
/// [PermissionsService.openSettings].
class PermissionExplainerSheet extends StatelessWidget {
  const PermissionExplainerSheet({
    super.key,
    required this.title,
    required this.body,
    required this.result,
    required this.service,
  });

  final String title;
  final String body;
  final PermissionResult result;
  final PermissionsService service;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    required PermissionResult result,
    required PermissionsService service,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => PermissionExplainerSheet(
        title: title,
        body: body,
        result: result,
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showSettingsAction = result.isFinalDenial;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tokens.text.headlineMd),
          const SizedBox(height: 12),
          Text(body, style: tokens.text.bodyLg),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  showSettingsAction ? 'Not now' : 'OK',
                  style: TextStyle(color: tokens.colors.onSurfaceMuted),
                ),
              ),
              if (showSettingsAction) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await service.openSettings();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Open settings'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

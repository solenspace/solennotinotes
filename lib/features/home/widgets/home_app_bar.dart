import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/inbox/cubit/inbox_badge_cubit.dart';
import 'package:noti_notes_app/features/inbox/screen.dart';
import 'package:noti_notes_app/features/search/cubit/search_cubit.dart';
import 'package:noti_notes_app/features/settings/screen.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_state.dart';
import 'package:noti_notes_app/features/user_info/screen.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Large collapsing app bar with greeting, profile/settings actions, and a
/// persistent search field at the bottom edge.
class HomeAppBar extends StatefulWidget {
  const HomeAppBar({super.key});

  @override
  State<HomeAppBar> createState() => _HomeAppBarState();
}

class _HomeAppBarState extends State<HomeAppBar> {
  bool _isSearching = false;
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NotiIdentityState identityState = context.watch<NotiIdentityCubit>().state;
    final identity = identityState.identity;
    final greeting = identityState.greetingFor(DateTime.now());
    final scheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      expandedHeight: 140, // Reduced since search bar is no longer below
      pinned: true,
      stretch: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(
          left: SpacingPrimitives.lg,
          right: SpacingPrimitives.lg,
          bottom: SpacingPrimitives.lg, // Standard padding now
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Text(
              greeting,
              style: Theme.of(context).textTheme.displayMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ),
      actions: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          // When expanded, the width is W - 32.
          // With a right margin of 16, it leaves exactly 16px on the left side,
          // perfectly aligning with the SpacingPrimitives.lg (16px) title padding on all devices.
          width: _isSearching ? MediaQuery.of(context).size.width - 32 : 48,
          height: 48,
          margin: EdgeInsets.only(right: _isSearching ? 16 : 8),
          decoration: BoxDecoration(
            color: _isSearching ? scheme.surfaceContainerHighest : Colors.transparent,
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isSearching)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (value) {
                        final cubit = context.read<SearchCubit>();
                        if (value.isEmpty) {
                          cubit.deactivate();
                        } else {
                          cubit.activateByTitle();
                        }
                        cubit.setQuery(value);
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: context.l10n.home_search_hint,
                        hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        fillColor: Colors.transparent,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
                color: scheme.onSurface,
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (_isSearching) {
                      _searchFocusNode.requestFocus();
                    } else {
                      _searchFocusNode.unfocus();
                      _searchController.clear();
                      context.read<SearchCubit>().deactivate();
                    }
                  });
                },
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          // Trailing cluster: inbox badge (48) + profile avatar (4 + 36 + 4) + settings (48) + 8.
          // Shrinking to 0.0 effectively removes them from the layout smoothly.
          width: _isSearching ? 0.0 : 148.0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _InboxBadgeButton(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed(UserInfoScreen.routeName),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                        border: Border.all(color: scheme.outline, width: 1.0),
                        image: identity?.profilePicture != null
                            ? DecorationImage(
                                image: FileImage(
                                  File(identity!.profilePicture!.path),
                                ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: identity?.profilePicture == null
                          ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant, size: 20)
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: context.l10n.home_settings_tooltip,
                  onPressed: () => Navigator.of(context).pushNamed(SettingsScreen.routeName),
                ),
                const Gap(8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Inbox action with a count badge driven by [InboxBadgeCubit]. The badge
/// hides itself at count 0 so the AppBar reads quiet for users who have
/// never received a share. Tapping always opens the inbox screen.
class _InboxBadgeButton extends StatelessWidget {
  const _InboxBadgeButton();

  @override
  Widget build(BuildContext context) {
    final count = context.watch<InboxBadgeCubit>().state;
    final tokens = context.tokens;
    return IconButton(
      tooltip: count > 0
          ? context.l10n.home_inbox_tooltip_count(count)
          : context.l10n.home_inbox_tooltip,
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        backgroundColor: tokens.colors.accent,
        textColor: tokens.colors.onAccent,
        child: const Icon(Icons.inbox_outlined),
      ),
      onPressed: () => Navigator.of(context).pushNamed(InboxScreen.routeName),
    );
  }
}

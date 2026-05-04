import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:noti_notes_app/features/search/legacy/search_provider.dart';
import 'package:noti_notes_app/features/settings/screen.dart';
import 'package:noti_notes_app/features/user_info/legacy/user_data_provider.dart';
import 'package:noti_notes_app/features/user_info/screen.dart';
import 'package:noti_notes_app/theme/app_tokens.dart';

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
    final userData = context.watch<UserData>();
    final user = userData.curentUserData;
    final greeting = userData.greeting();
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
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg, // Standard padding now
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Text(
              user.name.isEmpty ? greeting : '$greeting, ${user.name}',
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
          // perfectly aligning with the AppSpacing.lg (16px) title padding on all devices.
          width: _isSearching ? MediaQuery.of(context).size.width - 32 : 48,
          height: 48,
          margin: EdgeInsets.only(right: _isSearching ? 16 : 8),
          decoration: BoxDecoration(
            color: _isSearching ? scheme.surfaceContainerHighest : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        if (value.isEmpty) {
                          context.read<Search>().deactivateSearch();
                        } else {
                          context.read<Search>().activateSearchByTitle();
                        }
                        context.read<Search>().setSearchQuery(value);
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Search notes...',
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
                      context.read<Search>().deactivateSearch();
                      context.read<Search>().setSearchQuery('');
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
          // Exactly 100px is needed for the trailing icons (8 + 36 + 48 + 8).
          // Shrinking to 0.0 effectively removes them from the layout smoothly.
          width: _isSearching ? 0.0 : 100.0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed(UserInfoScreen.routeName),
                    child: Container(
                      width: 36,
                      height: 36,
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
                          ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant, size: 20)
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../config/routes.dart';
import '../../config/settings_catalog.dart';
import '../../config/theme.dart';
import '../../utils/url_helper.dart';
import '../../widgets/app_list_row.dart';
import 'settings_search.dart';

/// The Settings search box.
///
/// Sized off the theme rather than by hand: the field it replaces used a 13.5px
/// text style and 10px of vertical padding, which came out roughly 38px tall —
/// under the app's own 44 minimum and smaller than every other input.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search settings',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      borderSide: BorderSide(color: AppTheme.dividerC(context)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textTer(context),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 19,
                color: AppTheme.iconMute(context),
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.inputFill(context),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                borderSide: BorderSide(
                  color: AppTheme.primary(context),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// The result list for a settings search.
///
/// Each row shows the setting and, underneath, where it lives — without the
/// breadcrumb a list of bare titles gives no clue which page a tap will open.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({
    super.key,
    required this.hits,
    required this.query,
    required this.onOpen,
  });

  final List<SettingsSearchHit> hits;
  final String query;
  final void Function(SettingsLeaf leaf) onOpen;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) return _NoMatches(query: query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < hits.length; i++)
          AppListRow(
            key: ValueKey(hits[i].leaf.id),
            index: i,
            icon: hits[i].leaf.icon,
            accent: hits[i].leaf.accent,
            title: hits[i].leaf.title,
            subtitle: hits[i].breadcrumb,
            onTap: () => onOpen(hits[i].leaf),
          ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: AppTheme.emptyIcon(context),
          ),
          const SizedBox(height: AppTheme.spacingMD),
          Text('Nothing matches "$query"', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Try a different word, or clear the search.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Navigates to [leaf], wherever it lives.
///
/// The one place the web-vs-native legal branch exists — it used to be repeated
/// at all four call sites. Anchors ride along as the route argument so the
/// destination can scroll to the group the result named.
void openSetting(BuildContext context, SettingsLeaf leaf) {
  final destination = leaf.destination;
  if (destination is LinkTarget) {
    if (kIsWeb) {
      openUrl(context, destination.url);
    } else {
      Navigator.pushNamed(context, destination.nativeRoute);
    }
    return;
  }
  final route = routeOf(destination);
  if (route == AppRoutes.settings) return;
  Navigator.pushNamed(context, route, arguments: anchorOf(destination));
}

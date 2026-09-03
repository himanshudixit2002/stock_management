import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../utils/debouncer.dart';

/// One choice in an [AdminSearchBar]'s filter row.
class AdminFilter<T> {
  const AdminFilter({required this.value, required this.label, this.count});

  final T value;
  final String label;

  /// Optional badge, e.g. how many rows match this filter.
  final int? count;
}

/// A debounced search field with an optional filter-chip row and sort menu.
///
/// Every list screen in the app had hand-rolled its own `TextField` + chips,
/// which is fine for one screen and unmanageable across a console with a dozen
/// lists. Debouncing lives here so no caller has to remember it.
class AdminSearchBar<F, S> extends StatefulWidget {
  const AdminSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.filters = const [],
    this.selectedFilter,
    this.onFilterChanged,
    this.sorts = const [],
    this.selectedSort,
    this.onSortChanged,
    this.trailing,
    this.initialValue = '',
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  final List<AdminFilter<F>> filters;
  final F? selectedFilter;
  final ValueChanged<F>? onFilterChanged;

  final List<AdminFilter<S>> sorts;
  final S? selectedSort;
  final ValueChanged<S>? onSortChanged;

  /// Actions pinned to the right of the search field, e.g. an export button.
  final List<Widget>? trailing;

  final String initialValue;

  @override
  State<AdminSearchBar<F, S>> createState() => _AdminSearchBarState<F, S>();
}

class _AdminSearchBarState<F, S> extends State<AdminSearchBar<F, S>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final Debouncer _debouncer = Debouncer();

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debouncer.run(() {
      if (mounted) widget.onChanged(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  // Driven by the controller: reading _controller.text during
                  // build meant the clear button only appeared once the parent
                  // happened to rebuild, ~300ms after the first keystroke.
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Clear',
                            onPressed: () {
                              // Cancel first: a keystroke still in the debouncer
                              // would fire afterwards and restore the old query
                              // while the field read empty.
                              _debouncer.cancel();
                              _controller.clear();
                              widget.onChanged('');
                            },
                          ),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.sorts.isNotEmpty && widget.onSortChanged != null) ...[
              const SizedBox(width: 8),
              PopupMenuButton<S>(
                tooltip: 'Sort',
                icon: const Icon(Icons.swap_vert_rounded),
                onSelected: widget.onSortChanged,
                itemBuilder: (_) => [
                  for (final sort in widget.sorts)
                    PopupMenuItem<S>(
                      value: sort.value,
                      child: Row(
                        children: [
                          Icon(
                            sort.value == widget.selectedSort
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(sort.label),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            ...?widget.trailing,
          ],
        ),
        if (widget.filters.isNotEmpty && widget.onFilterChanged != null) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in widget.filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: filter.value == widget.selectedFilter,
                      label: Text(
                        filter.count == null
                            ? filter.label
                            : '${filter.label} (${filter.count})',
                      ),
                      onSelected: (_) => widget.onFilterChanged!(filter.value),
                      showCheckmark: false,
                      selectedColor: AppTheme.primaryColor.withValues(
                        alpha: 0.16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

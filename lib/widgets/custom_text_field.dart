import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/motion.dart';
import '../config/theme.dart';

class CustomTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool enabled;
  final void Function(String)? onChanged;
  final Iterable<String>? autofillHints;
  final bool showValidationIcons;
  final GlobalKey<FormFieldState>? formFieldKey;

  /// What the keyboard's action key does — `next` to move to the following
  /// field, `done` to submit.
  ///
  /// Without this every field in the app showed "done" and there was no way to
  /// chain them, because this widget owned its FocusNode privately.
  final TextInputAction? textInputAction;

  /// An externally owned focus node, so a form can move focus between fields.
  ///
  /// When null the widget creates and disposes its own, as before.
  final FocusNode? focusNode;

  /// Fired when the action key is pressed. Pair with [textInputAction] to get
  /// next-field traversal or submit-on-enter.
  final void Function(String)? onSubmitted;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.autofillHints,
    this.showValidationIcons = false,
    this.formFieldKey,
    this.textInputAction,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  /// Only set when the caller did not supply one — a node this widget did not
  /// create must not be disposed here.
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  bool? _validationResult; // null = not validated, true = valid, false = error
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _ownedFocusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(CustomTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode?.removeListener(_onFocusChange);
    _ownedFocusNode?.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _ownedFocusNode ??= FocusNode();
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _hasFocus && mounted) {
      setState(() => _hasFocus = focused);
    }
    if (!focused) {
      _runValidation();
    }
  }

  void _runValidation() {
    if (widget.validator == null || !widget.showValidationIcons) return;
    final result = widget.validator!(widget.controller.text);
    if (mounted) {
      setState(
        () => _validationResult = result != null
            ? false
            : (widget.controller.text.trim().isNotEmpty ? true : null),
      );
    }
  }

  InputBorder? _buildBorder(
    BuildContext context, {
    required Color color,
    double width = 2,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: widget.label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      hintText: widget.hint,
      hintStyle: TextStyle(fontSize: 14, color: AppTheme.textSec(context)),
      helperText: widget.helperText,
      helperMaxLines: 2,
      prefixIcon: widget.prefixIcon != null
          ? Icon(widget.prefixIcon, color: AppTheme.textSec(context))
          : null,
      suffix: widget.suffix,
      suffixIcon: _buildSuffixIcon(context),
      focusedBorder: widget.showValidationIcons && _validationResult == true
          ? _buildBorder(context, color: AppTheme.successColor)
          : null,
      errorBorder: widget.showValidationIcons
          ? _buildBorder(context, color: AppTheme.dangerColor, width: 1)
          : null,
      focusedErrorBorder: widget.showValidationIcons
          ? _buildBorder(context, color: AppTheme.dangerColor)
          : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingLG),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (_, _) {
          final field = TextFormField(
            key: widget.formFieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted == null
                ? null
                : (value) => widget.onSubmitted!(value),
            inputFormatters: widget.inputFormatters,
            validator: (v) {
              final result = widget.validator?.call(v);
              if (widget.showValidationIcons && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _validationResult = result != null
                          ? false
                          : (v?.trim().isNotEmpty == true ? true : null);
                    });
                  }
                });
              }
              return result;
            },
            maxLines: widget.maxLines,
            enabled: widget.enabled,
            onChanged: (v) {
              if (widget.showValidationIcons && _validationResult != null) {
                _runValidation();
              }
              widget.onChanged?.call(v);
            },
            autofillHints: widget.autofillHints,
            style: TextStyle(fontSize: 16, color: AppTheme.textPri(context)),
            decoration: decoration,
          );

          if (reduceMotion(context)) return field;

          // Subtle primary-color glow that animates in while the field is
          // focused (skipped when the field is showing a validation error).
          final showGlow = _hasFocus && _validationResult != false;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: showGlow
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.18),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: field,
          );
        },
      ),
    );
  }

  Widget? _buildSuffixIcon(BuildContext context) {
    if (!widget.showValidationIcons || _validationResult == null) return null;
    final icon = _validationResult!
        ? Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successColor,
            size: 22,
          )
        : Icon(Icons.cancel_rounded, color: AppTheme.dangerColor, size: 22);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: KeyedSubtree(key: ValueKey(_validationResult), child: icon),
    );
  }
}

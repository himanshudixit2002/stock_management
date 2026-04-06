import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  final _focusNode = FocusNode();
  bool? _validationResult; // null = not validated, true = valid, false = error

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
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
          return TextFormField(
            key: widget.formFieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../utils/unit_conversion.dart';
import 'animations.dart';

class QuantityStepper extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String? Function(String?)? validator;
  final int unitsPerPack;
  final String packUnit;
  final String baseUnit;

  const QuantityStepper({
    super.key,
    required this.controller,
    this.label,
    this.validator,
    this.unitsPerPack = 1,
    this.packUnit = 'box',
    this.baseUnit = 'pcs',
  });

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final TextEditingController _packController;
  late final TextEditingController _pieceController;

  /// Drives a brief scale bounce on the value field when changed via controls.
  bool _bump = false;

  bool get _isMixed => widget.unitsPerPack > 1;

  void _triggerBump() {
    if (!mounted) return;
    setState(() => _bump = true);
    Future.delayed(const Duration(milliseconds: 130), () {
      if (mounted) setState(() => _bump = false);
    });
  }

  void _increment(int amount) {
    final current = int.tryParse(widget.controller.text) ?? 0;
    final newVal = current + amount;
    if (newVal >= 0) {
      widget.controller.text = '$newVal';
      _syncFromTotal();
      _triggerBump();
    }
  }

  @override
  void initState() {
    super.initState();
    _packController = TextEditingController();
    _pieceController = TextEditingController();
    widget.controller.addListener(_syncFromTotal);
    _syncFromTotal();
  }

  @override
  void didUpdateWidget(covariant QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromTotal);
      widget.controller.addListener(_syncFromTotal);
      _syncFromTotal();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromTotal);
    _packController.dispose();
    _pieceController.dispose();
    super.dispose();
  }

  void _syncFromTotal() {
    if (!_isMixed) return;
    final total = int.tryParse(widget.controller.text) ?? 0;
    final split = splitBaseQuantity(
      baseQuantity: total,
      unitsPerPack: widget.unitsPerPack,
    );
    final nextPack = split.packs.toString();
    final nextPiece = split.pieces.toString();
    if (_packController.text != nextPack) {
      _packController.text = nextPack;
    }
    if (_pieceController.text != nextPiece) {
      _pieceController.text = nextPiece;
    }
  }

  void _updateTotalFromMixed() {
    final packs = int.tryParse(_packController.text) ?? 0;
    final pieces = int.tryParse(_pieceController.text) ?? 0;
    final total = toBaseQuantity(
      packs: packs,
      pieces: pieces,
      unitsPerPack: widget.unitsPerPack,
    );
    if (widget.controller.text != total.toString()) {
      widget.controller.text = '$total';
    }
  }

  /// Wraps [child] in a quick scale bounce when the value changes via the
  /// controls. Honors reduce-motion (no scaling).
  Widget _bounce(BuildContext context, Widget child) {
    if (reduceMotion(context)) return child;
    return AnimatedScale(
      scale: _bump ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _isMixed
                  ? '${widget.label!} (${widget.packUnit} + ${widget.baseUnit})'
                  : widget.label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        Row(
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              onTap: () => _increment(-1),
              onLongPress: () => _increment(-(_isMixed ? widget.unitsPerPack : 10)),
              color: AppTheme.dangerColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _isMixed
                  ? Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _packController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: widget.packUnit,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: AppTheme.inputFill(context),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => _updateTotalFromMixed(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _pieceController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: widget.baseUnit,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: AppTheme.inputFill(context),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => _updateTotalFromMixed(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _bounce(
                          context,
                          TextFormField(
                            controller: widget.controller,
                            readOnly: true,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSec(context),
                            ),
                            decoration: InputDecoration(
                              labelText: 'Total (${widget.baseUnit})',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: AppTheme.inputFill(context),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                            ),
                            validator: widget.validator,
                          ),
                        ),
                      ],
                    )
                  : _bounce(
                      context,
                      TextFormField(
                        controller: widget.controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppTheme.inputFill(context),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: widget.validator,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            _StepperButton(
              icon: Icons.add_rounded,
              onTap: () => _increment(1),
              onLongPress: () => _increment(_isMixed ? widget.unitsPerPack : 10),
              color: AppTheme.successColor,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: (_isMixed
                  ? [widget.unitsPerPack, widget.unitsPerPack * 2, widget.unitsPerPack * 5]
                  : [5, 10, 25, 50, 100])
              .map(
                (v) => ActionChip(
                  label: Text('+$v'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _increment(v);
                  },
                  backgroundColor: AppTheme.primaryColor.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Color color;

  const _StepperButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final visual = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 24),
    );

    // PlayfulPressable owns the tap (press scale + haptic). A wrapping
    // GestureDetector keeps the existing long-press bulk increment; tap and
    // long-press still compete correctly in the shared pointer arena.
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.selectionClick();
        onLongPress();
      },
      child: PlayfulPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: visual,
      ),
    );
  }
}

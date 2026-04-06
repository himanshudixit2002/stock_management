import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class QuantityStepper extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? Function(String?)? validator;

  const QuantityStepper({
    super.key,
    required this.controller,
    this.label,
    this.validator,
  });

  void _increment(int amount) {
    final current = int.tryParse(controller.text) ?? 0;
    final newVal = current + amount;
    if (newVal >= 0) {
      controller.text = '$newVal';
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label!,
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
              onLongPress: () => _increment(-10),
              color: AppTheme.dangerColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: controller,
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: validator,
              ),
            ),
            const SizedBox(width: 12),
            _StepperButton(
              icon: Icons.add_rounded,
              onTap: () => _increment(1),
              onLongPress: () => _increment(10),
              color: AppTheme.successColor,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 25, 50, 100]
              .map(
                (v) => ActionChip(
                  label: Text('+$v'),
                  onPressed: () => _increment(v),
                  backgroundColor:
                      AppTheme.primaryColor.withValues(alpha: 0.08),
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

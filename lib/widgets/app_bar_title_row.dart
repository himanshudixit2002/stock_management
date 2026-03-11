import 'package:flutter/material.dart';

class AppBarTitleRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  const AppBarTitleRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(title),
      ],
    );
  }
}

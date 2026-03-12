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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(title),
      ],
    );
  }
}

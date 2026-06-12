import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'animations.dart';

class AppBarTitleRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  /// Optional secondary line shown beneath the title; fades + slides in.
  final String? subtitle;

  const AppBarTitleRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (subtitle == null)
          Text(title)
        else
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              FadeSlideIn(
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

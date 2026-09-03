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
    // Flexible + ellipsis throughout: several callers pass user-supplied text
    // (a workspace name, a customer name), and a Row of bare Text inside an
    // AppBar overflows on a narrow phone rather than truncating.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (subtitle == null)
          Flexible(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          )
        else
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                FadeSlideIn(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

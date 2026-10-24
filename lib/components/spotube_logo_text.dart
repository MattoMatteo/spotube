import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The "Spotube" wordmark (sidebar and compact home app bar) with this fork's
/// "Matteo Edition" tag below it, aligned to the right.
class SpotubeLogoText extends StatelessWidget {
  const SpotubeLogoText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "Spotube",
          style: TextStyle(
            fontFamily: "Cookie",
            fontSize: 30,
            letterSpacing: 1.8,
            color: theme.colorScheme.foreground,
            height: 1,
          ),
        ),
        Text(
          "Matteo Edition",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            // Plain yellow is unreadable on the light theme
            color: isDark ? Colors.yellow[400] : Colors.amber[700],
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

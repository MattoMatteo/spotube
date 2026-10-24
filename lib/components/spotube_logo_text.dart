import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The "Spotube" wordmark (sidebar and compact home app bar) with this fork's
/// "Matteo Edition" tag below it, aligned to the right.
///
/// Styles are set with [DefaultTextStyle] (which replaces the inherited style)
/// rather than Text.style (which merges with it): the inherited shadcn theme
/// style carries its font package, so a merged "Cookie" font isn't found and
/// the fallback font is used.
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
        DefaultTextStyle(
          style: TextStyle(
            fontFamily: "Cookie",
            fontSize: 30,
            letterSpacing: 1.8,
            color: theme.colorScheme.foreground,
          ),
          child: const Text("Spotube"),
        ),
        DefaultTextStyle(
          // The app font, from the theme's typography (complete style)
          style: theme.typography.xSmall.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            // Plain yellow is unreadable on the light theme
            color: isDark ? Colors.yellow[400] : Colors.amber[700],
            height: 1,
          ),
          child: const Text("Matteo Edition"),
        ),
      ],
    );
  }
}

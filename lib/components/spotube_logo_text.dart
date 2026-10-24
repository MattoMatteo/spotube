import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The "Spotube" wordmark (sidebar and compact home app bar) with this fork's
/// "Matteo Edition" tag below it, aligned to the right.
///
/// Styles are set with [DefaultTextStyle] (which replaces the inherited style)
/// rather than Text.style (which merges with it): the inherited shadcn theme
/// style carries its font package, so a merged "Cookie" font isn't found and
/// the fallback font is used. Both lines use the Cookie script font.
class SpotubeLogoText extends StatelessWidget {
  const SpotubeLogoText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Loose constraints (the navigation label may pass tight/wide ones) but
    // still shrink-wrapped like the plain text was; IntrinsicWidth makes the
    // column exactly as wide as "Spotube", so the tag ends under its last letter.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              // Same Cookie script as the wordmark, smaller, like a subscript
              style: TextStyle(
                fontFamily: "Cookie",
                // Clearly narrower than "Spotube", or right-aligned looks centered
                fontSize: 12,
                letterSpacing: 0.2,
                // Plain yellow is unreadable on the light theme
                color: isDark ? Colors.yellow[400] : Colors.amber[700],
                height: 0.8,
              ),
              textAlign: TextAlign.right,
              child: const Text("Matteo Edition"),
            ),
          ],
        ),
      ),
    );
  }
}

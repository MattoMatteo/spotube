import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The app's wordmark (sidebar and compact home app bar), in the Cookie
/// script font like the original Spotube one.
///
/// The style is set with [DefaultTextStyle] (which replaces the inherited
/// style) rather than Text.style (which merges with it): the inherited shadcn
/// theme style carries its font package, so a merged "Cookie" font isn't found
/// and the fallback font is used.
class AppLogoText extends StatelessWidget {
  const AppLogoText({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: "Cookie",
        fontSize: 30,
        letterSpacing: 1.8,
        color: Theme.of(context).colorScheme.foreground,
      ),
      child: const Text("Matubefy"),
    );
  }
}

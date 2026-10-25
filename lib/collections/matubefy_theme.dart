import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The gradient of the Matubefy logo (assets/branding/source)
const matubefyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFB86B), Color(0xFFFF5E7E)],
);

/// The default color scheme, built around the logo: dark slate-blue surfaces
/// like its background, and a coral from the middle of its gradient as the
/// only accent, so the UI stays calm and the gradient stands out where used
ColorScheme matubefyColorScheme(ThemeMode mode) {
  return mode == ThemeMode.light ? _light : _dark;
}

const _dark = ColorScheme(
  brightness: Brightness.dark,
  background: Color(0xFF1C1F26),
  foreground: Color(0xFFECEAE7),
  card: Color(0xFF23262F),
  cardForeground: Color(0xFFECEAE7),
  popover: Color(0xFF262A33),
  popoverForeground: Color(0xFFECEAE7),
  primary: Color(0xFFFF8070),
  primaryForeground: Color(0xFF1C1F26),
  secondary: Color(0xFF2C303A),
  secondaryForeground: Color(0xFFECEAE7),
  muted: Color(0xFF2A2E38),
  mutedForeground: Color(0xFF9A9FAD),
  accent: Color(0xFF2F333E),
  accentForeground: Color(0xFFECEAE7),
  destructive: Color(0xFFD9404F),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFF30343F),
  input: Color(0xFF343845),
  ring: Color(0xFFFF8070),
  chart1: Color(0xFFFFB86B),
  chart2: Color(0xFFFF5E7E),
  chart3: Color(0xFFFF8B74),
  chart4: Color(0xFF7AA2F7),
  chart5: Color(0xFF9ECE6A),
  sidebar: Color(0xFF1A1D23),
  sidebarForeground: Color(0xFFECEAE7),
  sidebarPrimary: Color(0xFFFF8070),
  sidebarPrimaryForeground: Color(0xFF1C1F26),
  sidebarAccent: Color(0xFF2A2E38),
  sidebarAccentForeground: Color(0xFFECEAE7),
  sidebarBorder: Color(0xFF2A2E38),
  sidebarRing: Color(0xFFFF8070),
);

const _light = ColorScheme(
  brightness: Brightness.light,
  background: Color(0xFFFAF8F6),
  foreground: Color(0xFF242832),
  card: Color(0xFFFFFFFF),
  cardForeground: Color(0xFF242832),
  popover: Color(0xFFFFFFFF),
  popoverForeground: Color(0xFF242832),
  // Darker than the dark one, to stay readable on white
  primary: Color(0xFFE8506A),
  primaryForeground: Color(0xFFFFFFFF),
  secondary: Color(0xFFF0ECE9),
  secondaryForeground: Color(0xFF242832),
  muted: Color(0xFFF0ECE9),
  mutedForeground: Color(0xFF6B7080),
  accent: Color(0xFFEEE8E4),
  accentForeground: Color(0xFF242832),
  destructive: Color(0xFFD92D3F),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFFE4DEDA),
  input: Color(0xFFE4DEDA),
  ring: Color(0xFFE8506A),
  chart1: Color(0xFFF59E3D),
  chart2: Color(0xFFE8506A),
  chart3: Color(0xFFF07A5E),
  chart4: Color(0xFF4C6EF5),
  chart5: Color(0xFF5FA83A),
  sidebar: Color(0xFFF4F1EE),
  sidebarForeground: Color(0xFF242832),
  sidebarPrimary: Color(0xFFE8506A),
  sidebarPrimaryForeground: Color(0xFFFFFFFF),
  sidebarAccent: Color(0xFFEEE8E4),
  sidebarAccentForeground: Color(0xFF242832),
  sidebarBorder: Color(0xFFE4DEDA),
  sidebarRing: Color(0xFFE8506A),
);

/// Whether [colorScheme] is the Matubefy one: the gradient is only used with
/// it, it would clash with the other color schemes
bool isMatubefyColorScheme(ColorScheme colorScheme) {
  return colorScheme.primary == _dark.primary ||
      colorScheme.primary == _light.primary;
}

/// A primary button filled with [matubefyGradient] instead of the primary color
final AbstractButtonStyle matubefyGradientButton =
    ButtonVariance.primary.copyWith(
  decoration: (context, states, decoration) {
    if (states.contains(WidgetState.disabled) ||
        decoration is! BoxDecoration ||
        !isMatubefyColorScheme(Theme.of(context).colorScheme)) {
      return decoration;
    }
    return decoration.copyWith(gradient: matubefyGradient);
  },
);

/// Paints [child] with [matubefyGradient], keeping its opacity: a slider gets
/// a bright played part and a faint rest
class MatubefyGradientMask extends StatelessWidget {
  final Widget child;

  const MatubefyGradientMask({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isMatubefyColorScheme(Theme.of(context).colorScheme)) return child;

    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: matubefyGradient.createShader,
      child: child,
    );
  }
}

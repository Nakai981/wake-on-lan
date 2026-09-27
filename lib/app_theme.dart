import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

final appThemeMode = ValueNotifier(ThemeMode.light);

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: const Color(0xFF0D1422),
    primary: const Color(0xFF96B7FF),
    onSurface: const Color(0xFFE7EDFA),
    onSurfaceVariant: const Color(0xFF9AAAC4),
    primaryContainer: const Color(0xFF233758),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: uiFont,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        textStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
    ),
  );
}

class AppearanceSwitch extends StatelessWidget {
  const AppearanceSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      toggled: dark,
      label: 'Giao diện tối',
      child: Tooltip(
        message: dark ? 'Chuyển giao diện sáng' : 'Chuyển giao diện tối',
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () =>
              appThemeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 76,
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF243551) : const Color(0xFFE4ECFA),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedAlign(
                    alignment: dark
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF476BA9) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.light_mode_rounded,
                          size: 18,
                          color: dark
                              ? Colors.white38
                              : const Color(0xFFB87C1D),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.dark_mode_rounded,
                          size: 18,
                          color: dark ? Colors.white : const Color(0xFF8897AD),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

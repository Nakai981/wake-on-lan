import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services.dart';
import 'screens.dart';
import 'design.dart';
import 'agent_client.dart';
import 'app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Be Vietnam Pro'], license);
  });
  final prefs = await SharedPreferences.getInstance();
  runApp(WakeApp(store: DeviceStore(prefs)));
}

const ink = navy;
const green = accent;
const paper = Color(0xFFF2F5FA);

class WakeApp extends StatelessWidget {
  final DeviceStore store;
  final NetworkService? network;
  final AgentClient? agentClient;
  const WakeApp({
    super.key,
    required this.store,
    this.network,
    this.agentClient,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: appThemeMode,
    builder: (context, mode, _) => MaterialApp(
      themeMode: mode,
      darkTheme: buildDarkTheme(),
      title: 'Wake My PC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: uiFont,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          onPrimary: Colors.white,
          primaryContainer: soft,
          onPrimaryContainer: accent,
          secondary: const Color(0xFF087F9C),
          secondaryContainer: const Color(0xFFDFF7FB),
          surface: paper,
          onSurface: navy,
          onSurfaceVariant: muted,
          outline: const Color(0xFF8395AB),
          outlineVariant: const Color(0xFFDCE5EF),
          error: const Color(0xFFCE3956),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: navy,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          titleTextStyle: TextStyle(
            fontFamily: uiFont,
            color: navy,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
            height: 1.3,
            color: navy,
          ),
          headlineMedium: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
            height: 1.35,
            color: navy,
          ),
          bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: navy),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: navy),
          bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(18),
          labelStyle: const TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            textStyle: const TextStyle(
              fontFamily: uiFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 54),
            side: const BorderSide(color: Color(0xFFCFDCEA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xFFE1E8F0)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: paper,
          showDragHandle: true,
          dragHandleColor: Color(0xFFCBD5E1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE1E8F0),
          thickness: 1,
        ),
      ),
      home: HomePage(
        store: store,
        net: network ?? NetworkService(),
        agentClient: agentClient,
      ),
    ),
  );
}

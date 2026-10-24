import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env first
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp();
  await AppLanguage.instance.start();
  print("Firebase initialized");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bannerBlue = Colors.blueAccent;
    const appBackground = Color(0xFFF3F7FC);
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      locale: AppLanguage.instance.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('zh'),
        Locale('hi'),
        Locale('pt'),
        Locale('bn'),
        Locale('ru'),
        Locale('ja'),
        Locale('tr'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [_AppKeyboardNavObserver()],
      builder: (context, child) {
        return AppKeyboardScope(child: child ?? const SizedBox.shrink());
      },
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: bannerBlue,
          brightness: Brightness.light,
          surface: appBackground,
        ),
        scaffoldBackgroundColor: appBackground,
        canvasColor: appBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: bannerBlue,
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: bannerBlue,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: bannerBlue,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: bannerBlue,
        ),
      ),
      home: const Login(),
    );
      },
    );
  }
}

class _AppKeyboardNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppKeyboardController.instance.hide();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppKeyboardController.instance.hide();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppKeyboardController.instance.hide();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppKeyboardController.instance.hide();
  }
}
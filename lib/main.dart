import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:proyecto_app/auth/login_screen.dart';
import 'package:proyecto_app/firebase_options.dart';
import 'package:proyecto_app/home/main_navigation.dart';
import 'package:proyecto_app/theme/app_theme.dart';
import 'package:proyecto_app/theme/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> adminDemoNotifier = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  final prefs = await SharedPreferences.getInstance();
  final themeModeString = prefs.getString('theme_mode') ?? 'system';
  adminDemoNotifier.value = prefs.getBool('demo_admin_mode') ?? false;

  // Capturar código de invitación pendiente desde la URL
  final code = Uri.base.queryParameters['code'];
  if (code != null && code.isNotEmpty) {
    await prefs.setString('pending_join_code', code);
  }
  
  if (themeModeString == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (themeModeString == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.system;
  }

  await loadLanguage();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: languageNotifier,
          builder: (_, String currentLanguage, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Smart Budget',
              themeMode: currentMode,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              home: StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasData) {
                    return const MainNavigation();
                  }
                  return const LoginScreen();
                },
              ),
            );
          },
        );
      },
    );
  }
}

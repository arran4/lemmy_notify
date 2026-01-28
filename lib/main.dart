import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
      // size: Size(800, 600),
      // center: true,
      // backgroundColor: Colors.transparent,
      // skipTaskbar: false,
      // titleBarStyle: TitleBarStyle.hidden,
      );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // await windowManager.show();
    // await windowManager.focus();
  });

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: MyHomePage(),
    );
  }
}

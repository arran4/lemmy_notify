import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> implements TrayListener {
  int newPostsCount = 0;
  int newMessagesCount = 0;
  LemmyApiV3? lemmyClient;
  LoginResponse? authResponse;
  FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final String icon = Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';

  @override
  void initState() {
    super.initState();
    initLemmyClient();
    initSystemTray();
    // Start checking for updates
    Timer.periodic(const Duration(minutes: 5), (Timer timer) {
      checkForUpdates();
    });
  }

  Future<void> initLemmyClient() async {
    // Load user preferences
    final String? serverUrl = await SharedPreferences.getInstance().then((prefs) => prefs.getString('serverUrl') ?? '');
    final String? username = await SharedPreferences.getInstance().then((prefs) => prefs.getString('username') ?? '');
    final String? password = await secureStorage.read(key: 'password');

    lemmyClient = null;

    // Set up the Lemmy API client with user preferences
    if (serverUrl != null) {
      lemmyClient = LemmyApiV3(serverUrl);
    }
    if (lemmyClient != null && username != null && password != null) {
      authResponse = await lemmyClient?.run(Login(usernameOrEmail: username, password: password));
    }

  }

  Future<void> initSystemTray() async {
    // Set up the system tray icon
    trayManager.setIcon(
      icon, // Use a different icon if needed
    );
    if (!Platform.isLinux) {
      trayManager.setToolTip(
          'New Posts: $newPostsCount, New Messages: $newMessagesCount');
    }
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'settings',
          label: 'Settings',
        ),
      ],
    );
    trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  Future<void> showSettingsWindow() async {
    final prefs = await SharedPreferences.getInstance();
    final serverController = TextEditingController(text: prefs.getString('serverUrl') ?? '');
    final usernameController = TextEditingController(text: prefs.getString('username') ?? '');
    final passwordController = TextEditingController(text: '');

    if (!context.mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: Column(
            children: [
              TextField(
                controller: serverController,
                decoration: const InputDecoration(labelText: 'Lemmy Server URL'),
              ),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Save user preferences
                await prefs.setString('serverUrl', serverController.text);
                await prefs.setString('username', usernameController.text);

                // Save the password securely
                await secureStorage.write(key: 'password', value: passwordController.text);

                await initLemmyClient();
                // TODO verify it works.

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkForUpdates() async {
    try {
      if (lemmyClient == null) {
        return;
      }
      if (authResponse == null || authResponse!.jwt == null) {
        return;
      }
      // Fetch new posts
      final List<PostView> posts = await lemmyClient!.run(GetPosts(auth: authResponse!.jwt!.raw));

      // Fetch new messages
      final List<PrivateMessageView> messages = await lemmyClient!.run(GetPrivateMessages(unreadOnly: true, auth: authResponse!.jwt!.raw));

      // Update the counts
      setState(() {
        newPostsCount = posts.length;
        newMessagesCount = messages.length;
      });

      // Update the system tray icon with the new counts
      trayManager.setIcon(
        icon, // Use a different icon if needed
      );
      if (!Platform.isLinux) {
        trayManager.setToolTip('New Posts: $newPostsCount, New Messages: $newMessagesCount');
      }
    } catch (e) {
      if (context.mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lemmy Notifier'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('New Posts: $newPostsCount'),
            Text('New Messages: $newMessagesCount'),
          ],
        ),
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
  }

  @override
  void onTrayIconMouseUp() {
  }

  @override
  void onTrayIconRightMouseDown() {
  }

  @override
  void onTrayIconRightMouseUp() {
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'settings') {
      showSettingsWindow();
    }
  }
}
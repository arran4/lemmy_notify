import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
  int? newPostsCount;
  int? newMessagesCount;
  LemmyApiV3? lemmyClient;
  LoginResponse? authResponse;
  FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final String icon = Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';
  String? status;
  String? lastError;
  Timer? updateTimer;
  bool openMinimizedToSystemTray = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    initLemmyClient();
    initSystemTray();
    initTimer();
  }

  Future<void> initLemmyClient() async {
    lemmyClient = null;

    try {
      // Load user preferences
      final String? serverUrl = await SharedPreferences.getInstance().then((prefs) => prefs.getString('serverUrl') ?? '');
      final String? username = await SharedPreferences.getInstance().then((prefs) => prefs.getString('username') ?? '');
      final String? password = await secureStorage.read(key: 'password');

      if (serverUrl == null || username == null) {
        setState(() {
          status = 'Nothing configured';
        });
        return;
      }

      // Set up the Lemmy API client with user preferences
      lemmyClient = LemmyApiV3(serverUrl);
      if (lemmyClient != null && password != null) {
        authResponse = await lemmyClient?.run(Login(usernameOrEmail: username, password: password));
      }
      showSnackbar('Status: Loading');
    } catch (e) {
      showSnackbar('Error: $e');
      setState(() {
        status = 'Error';
        lastError = e.toString();
      });
    }
  }

  Future<void> initSystemTray() async {
    // Set up the system tray icon
    trayManager.setIcon(
      icon, // Use a different icon if needed
    );
    if (!Platform.isLinux) {
      trayManager.setToolTip('New Posts: ${newPostsCount ?? 'loading'}, New Messages: ${newMessagesCount ?? 'loading'}');
    }
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'refresh',
          label: 'Refresh Now',
        ),
        MenuItem(
          key: 'settings',
          label: 'Settings',
        ),
      ],
    );
    trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  Future<void> initTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final int timerInterval = prefs.getInt('timerInterval') ?? 5; // Default timer interval is 5 minutes
    updateTimer = Timer.periodic(Duration(minutes: timerInterval), (Timer timer) {
      checkForUpdates();
    });
  }

  Future<void> showSettingsWindow() async {
    final prefs = await SharedPreferences.getInstance();
    final serverController = TextEditingController(text: prefs.getString('serverUrl') ?? '');
    final usernameController = TextEditingController(text: prefs.getString('username') ?? '');
    final passwordController = TextEditingController(text: '');
    final timerIntervalController = TextEditingController(
        text: prefs.getInt('timerInterval') != null ? prefs.getInt('timerInterval').toString() : '5');

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
              TextField(
                controller: timerIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Timer Interval (minutes)'),
              ),
              Row(
                children: [
                  Checkbox(
                    value: openMinimizedToSystemTray,
                    onChanged: (value) {
                      setState(() {
                        openMinimizedToSystemTray = value ?? false;
                      });
                    },
                  ),
                  const Text('Open minimized to system tray'),
                ],
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
                await prefs.setInt('timerInterval', int.parse(timerIntervalController.text));

                // Save the password securely
                await secureStorage.write(key: 'password', value: passwordController.text);

                await initLemmyClient();
                await initTimer();

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
      setState(() {
        newPostsCount = null;
        newMessagesCount = null;
      });
      if (authResponse == null || authResponse!.jwt == null) {
        return;
      }
      // Fetch new posts
      final GetPostsResponse posts = await lemmyClient!.run(GetPosts(auth: authResponse!.jwt));

      // Fetch new messages
      final PrivateMessagesResponse messages = await lemmyClient!.run(
          GetPrivateMessages(unreadOnly: true, auth: authResponse!.jwt));

      // Update the counts
      setState(() {
        final int oldPostsCount = newPostsCount ?? 0;
        final int oldMessagesCount = newMessagesCount ?? 0;
        newPostsCount = posts.posts.where((PostView post) => post.read && post.unreadComments == 0).length;
        newMessagesCount = messages.privateMessages.length;

        showSnackbar('Status: Update Successful\n'
            'New Posts: $newPostsCount (Delta: ${newPostsCount! - oldPostsCount}), '
            'New Messages: $newMessagesCount (Delta: ${newMessagesCount! - oldMessagesCount})');
      });

      // Update the system tray icon with the new counts
      trayManager.setIcon(
        icon, // Use a different icon if needed
      );
      if (!Platform.isLinux) {
        trayManager.setToolTip(
            'New Posts: ${newPostsCount ?? 'loading'}, New Messages: ${newMessagesCount ?? 'loading'}');
      }
    } catch (e) {
      showSnackbar('Error: $e');
      setState(() {
        status = 'Error';
        lastError = e.toString();
      });
    }
  }

  void forceRefresh() {
    setState(() {
      status = 'loading';
    });
    checkForUpdates();
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      status = 'loading';
      checkForUpdates();
    }

    if (status == 'Error') {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Lemmy Notifier'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: showSettingsWindow,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: forceRefresh,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('Error:'),
              Text(lastError ?? 'Unknown Error'),
              ElevatedButton(
                onPressed: forceRefresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Lemmy Notifier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: showSettingsWindow,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: forceRefresh,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('New Posts: ${newPostsCount ?? 'loading'}'),
            Text('New Messages: ${newMessagesCount ?? 'loading'}'),
          ],
        ),
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // TODO: Implement
  }

  @override
  void onTrayIconMouseUp() {
    // TODO: Implement
  }

  @override
  void onTrayIconRightMouseDown() {
    // TODO: Implement
  }

  @override
  void onTrayIconRightMouseUp() {
    // TODO: Implement
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'refresh') {
      forceRefresh();
    } else if (menuItem.key == 'settings') {
      showSettingsWindow();
    }
  }
}

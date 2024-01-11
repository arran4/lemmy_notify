import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
  Future<LemmyApiV3?>? lemmyClient;
  LoginResponse? authResponse;
  FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  String iconNewPosts = Platform.isWindows ? 'images/tray_icon_new_posts.ico' : 'images/tray_icon_new_posts.png';
  String iconNewMessages = Platform.isWindows ? 'images/tray_icon_new_messages.ico' : 'images/tray_icon_new_messages.png';
  String iconDefault = Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';
  String currentIcon = Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';
  String? status;
  String? lastError;
  Timer? updateTimer;
  GetSiteResponse? siteResponse;
  final StreamController<String> _eventStreamController = StreamController<String>();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    lemmyClient = createLemmyClient();
    initSystemTray();
    initTimer();
    SharedPreferences.getInstance().then((prefs) => prefs.getBool('openMinimizedToSystemTray') ?? false).then((value) {
      if (!value) {

      }
    });
  }

  Future<LemmyApiV3?> createLemmyClient() async {
    try {
      // Load user preferences
      final String? serverUrl = await SharedPreferences.getInstance().then((prefs) => prefs.getString('serverUrl') ?? '');
      final String? username = await SharedPreferences.getInstance().then((prefs) => prefs.getString('username') ?? '');
      final String? password = await secureStorage.read(key: 'password');

      if (serverUrl == null || username == null) {
        setState(() {
          status = 'Nothing configured';
        });
        return null;
      }

      // Set up the Lemmy API client with user preferences
      LemmyApiV3 client = LemmyApiV3(serverUrl);
      if (password != null) {
        authResponse = await client.run(Login(usernameOrEmail: username, password: password));
      }
      setState(() {
        status = 'configured';
        siteResponse = null;
      });
      showSnackbar('Status: $status');

      GetSiteResponse sr = await client.run(GetSite(auth: authResponse!.jwt));
      setState(() {
        siteResponse = sr;
      });

      return client;
    } catch (e) {
      showSnackbar('Error: $e');
      setState(() {
        status = 'Error';
        lastError = e.toString();
      });
      return null;
    }
  }

  Future<void> initSystemTray() async {
    // Set up the system tray icon
    trayManager.setIcon(
      currentIcon, // Use a different icon if needed
    );
    if (!Platform.isLinux) {
      trayManager.setToolTip('New Posts: ${newPostsCount ?? 'initializing'}, New Messages: ${newMessagesCount ?? 'initializing'}');
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
    if (!context.mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: SettingsPage(savedResults: saveSettings, eventStream: _eventStreamController.stream),
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
                _eventStreamController.add("save");
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkForUpdates() async {
    LemmyApiV3? client = await lemmyClient;
    try {
      if (client == null) {
        return;
      }
      if (authResponse == null || authResponse!.jwt == null) {
        return;
      }
      setState(() {
        status = 'checking';
      });
      // Fetch new posts
      final GetPostsResponse posts = await client!.run(GetPosts(auth: authResponse!.jwt));

      // Fetch new messages
      final PrivateMessagesResponse messages = await client!.run(
          GetPrivateMessages(unreadOnly: true, auth: authResponse!.jwt));

      // Update the counts
      setState(() {
        final int oldPostsCount = newPostsCount ?? 0;
        final int oldMessagesCount = newMessagesCount ?? 0;
        newPostsCount = posts.posts.where((PostView post) => !post.read && post.unreadComments >= 0).length;
        newMessagesCount = messages.privateMessages.length;
        status = "updated";

        if (newMessagesCount! > oldMessagesCount) {
          currentIcon = iconNewMessages;
        } else if (newPostsCount! > oldPostsCount) {
          currentIcon = iconNewPosts;
        } else {
          currentIcon = iconDefault;
        }
        showSnackbar('Status: Update Successful\n'
            'New Posts: $newPostsCount (Delta: ${newPostsCount! - oldPostsCount}), '
            'New Messages: $newMessagesCount (Delta: ${newMessagesCount! - oldMessagesCount})\n'
            'Lemmy Instance: ${siteResponse?.siteView.site.name}');
      });

      // Update the system tray icon with the new counts
      trayManager.setIcon(
        currentIcon, // Use a different icon if needed
      );
      if (!Platform.isLinux) {
        trayManager.setToolTip(
            'New Posts: ${newPostsCount ?? 'initializing'}, New Messages: ${newMessagesCount ?? 'initializing'}');
      }
    } catch (e) {
      showSnackbar('Error: $e');
      setState(() {
        status = 'Error';
        lastError = e.toString();
      });
    }
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: RichText(
          text: TextSpan(
            text: message,
            style: const TextStyle(color: Colors.white),
            children: [
              if (siteResponse != null)
                TextSpan(
                  text: '\nLemmy Instance: ${siteResponse?.siteView.site.name}',
                  style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                ),
            ],
          ),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void forceRefresh() {
    setState(() {
      status = 'loading';
    });
    checkForUpdates();
  }

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      forceRefresh();
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

    // Custom style for the link
    TextStyle linkStyle = const TextStyle(
      color: Colors.blue,
      decoration: TextDecoration.underline,
    );

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
            if (siteResponse != null)
              Row(mainAxisAlignment: MainAxisAlignment.center,children: [
                const Text('Lemmy Instance: ', style: TextStyle(fontWeight: FontWeight.bold),),
                GestureDetector(
                  onTap: () {
                    if (siteResponse != null) {
                      launchUrlString(siteResponse!.siteView.site.actorId);
                    }
                  },
                  child: Text(
                    '${siteResponse?.siteView.site.name}',
                    style: linkStyle,
                  ),
                ),
              ],
            ),
            Text('New Posts: ${newPostsCount ?? 'initializing'}'),
            Text('New Messages: ${newMessagesCount ?? 'initializing'}'),
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

  void saveSettings(String serverUrl, String username, int timerInterval, String? password) async {
    final prefs = await SharedPreferences.getInstance();
    // Save user preferences
    await prefs.setString('serverUrl', serverUrl);
    await prefs.setString('username', username);
    await prefs.setInt('timerInterval', timerInterval);

    // Save the password securely
    if (password != null && password.isNotEmpty) {
      await secureStorage.write(key: 'password', value: password);
    }

    lemmyClient = createLemmyClient();
    await initTimer();
    forceRefresh();

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

typedef SettingsPageSavedResultsFunc = void Function(String serverUrl, String username, int timerInterval, String? password);

class SettingsPage extends StatefulWidget {
  final SettingsPageSavedResultsFunc? savedResults;
  final Stream<String> eventStream;

  SettingsPage({super.key, required this.eventStream, required this.savedResults});

  @override
  State<StatefulWidget> createState() {
    return _SettingsPageState();
  }
}

class _SettingsPageState extends State<SettingsPage> {
  bool openMinimizedToSystemTray = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then(((SharedPreferences prefs) {
      openMinimizedToSystemTray = prefs.getBool('openMinimizedToSystemTray')??openMinimizedToSystemTray;
      serverController.text = prefs.getString('serverUrl') ?? '';
      usernameController.text = prefs.getString('username') ?? '';
      passwordController.text = '';
      timerIntervalController.text = prefs.getInt('timerInterval') != null ? prefs.getInt('timerInterval').toString() : '5';
    }));
  }
  //
  late TextEditingController serverController = TextEditingController();
  late TextEditingController usernameController = TextEditingController();
  late TextEditingController passwordController = TextEditingController();
  late TextEditingController timerIntervalController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
        stream: widget.eventStream,
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.hasData && snapshot.data == "save") {
            if (widget.savedResults != null) {
              String? pwd = null;
              if (passwordController.text.isNotEmpty) {
                pwd = passwordController.text;
              }
              widget.savedResults!(serverController.text, usernameController.text, int.parse(timerIntervalController.text), pwd);
            }
          }
          return Column(
            children: [
              TextField(
                controller: serverController,
                decoration: const InputDecoration(
                    labelText: 'Lemmy Server URL'),
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
                decoration: const InputDecoration(
                    labelText: 'Timer Interval (minutes)'),
              ),
              CheckboxListTile(
                value: openMinimizedToSystemTray,
                title: const Text('Open minimized to system tray'),
                onChanged: (bool? value) async {
                  final prefs = SharedPreferences.getInstance();
                  await (await prefs).setBool('openMinimizedToSystemTray', value ?? false);
                  setState(() {
                    openMinimizedToSystemTray = value??false;
                  });
                },
              ),
            ],
          );
        }
    );
  }

}

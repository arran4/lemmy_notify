import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/clickable_link.dart';
import 'settings_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    implements TrayListener, WindowListener {
  int? newPostsCount;
  int? newMessagesCount;
  Future<LemmyApiV3?>? lemmyClient;
  LoginResponse? authResponse;
  FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  String iconNewPosts = Platform.isWindows
      ? 'images/tray_icon_new_posts.ico'
      : 'images/tray_icon_new_posts.png';
  String iconNewMessages = Platform.isWindows
      ? 'images/tray_icon_new_messages.ico'
      : 'images/tray_icon_new_messages.png';
  String iconDefault =
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';
  String currentIcon =
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';
  String? status;
  String? detailedStatusMessage;
  String? lastError;
  Timer? updateTimer;
  GetSiteResponse? siteResponse;
  GetPostsResponse? posts;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    windowManager.setPreventClose(true);
    windowManager.addListener(this);
    lemmyClient = createLemmyClient();
    initSystemTray();
    initTimer();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.getBool('openMinimizedToSystemTray') ?? false)
        .then((value) {
      if (!value) {
        windowManager.show();
        windowManager.focus();
      }
    });
  }

  Future<LemmyApiV3?> createLemmyClient() async {
    try {
      // Load user preferences
      final String? serverUrl = await SharedPreferences.getInstance()
          .then((prefs) => prefs.getString('serverUrl') ?? '');
      final String? username = await SharedPreferences.getInstance()
          .then((prefs) => prefs.getString('username') ?? '');
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
        authResponse = await client
            .run(Login(usernameOrEmail: username, password: password));
      }
      setState(() {
        status = 'configured';
        detailedStatusMessage = 'Status: $status';
        siteResponse = null;
      });

      GetSiteResponse sr = await client.run(GetSite(auth: authResponse?.jwt));
      setState(() {
        siteResponse = sr;
      });

      return client;
    } catch (e) {
      setState(() {
        status = 'Error';
        lastError = e.toString();
        detailedStatusMessage = 'Error: $e';
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
      trayManager.setToolTip(
          'New Posts: ${newPostsCount ?? 'initializing'}, New Messages: ${newMessagesCount ?? 'initializing'}');
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
        MenuItem(
          key: 'show',
          label: 'Show',
        ),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    );
    trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  Future<void> initTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final int timerInterval = prefs.getInt('timerInterval') ??
        5; // Default timer interval is 5 minutes
    updateTimer =
        Timer.periodic(Duration(minutes: timerInterval), (Timer timer) {
      checkForUpdates();
    });
  }

  Future<void> showSettingsWindow() async {
    if (!context.mounted) {
      return;
    }
    final StreamController<String> _eventStreamController =
        StreamController<String>();

    windowManager.show();
    windowManager.focus();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: SettingsPage(
              savedResults: saveSettings,
              eventStream: _eventStreamController.stream),
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
        detailedStatusMessage = 'Checking...';
      });
      // Fetch new posts
      posts = await client.run(GetPosts(
          auth: authResponse?.jwt,
          type: ListingType.all,
          sort: SortType.newComments));

      // Fetch new messages
      final PrivateMessagesResponse messages = await client
          .run(GetPrivateMessages(unreadOnly: true, auth: authResponse?.jwt));

      // Update the counts
      setState(() {
        final int oldPostsCount = newPostsCount ?? 0;
        final int oldMessagesCount = newMessagesCount ?? 0;
        newPostsCount = (posts?.posts??[])
            .where((PostView post) => !post.read || post.unreadComments > 0)
            .length;
        newMessagesCount = messages.privateMessages.length;
        status = "updated";

        if (newMessagesCount! > 0) {
          currentIcon = iconNewMessages;
        } else if (newPostsCount! > 0) {
          currentIcon = iconNewPosts;
        } else {
          currentIcon = iconDefault;
        }
        detailedStatusMessage = 'Status: Update Successful\n'
            'New Posts: $newPostsCount (Delta: ${newPostsCount! - oldPostsCount}), '
            'New Messages: $newMessagesCount (Delta: ${newMessagesCount! - oldMessagesCount})\n'
            'Lemmy Instance: ${siteResponse?.siteView.site.name}';
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
      setState(() {
        status = 'Error';
        lastError = e.toString();
        detailedStatusMessage = 'Error: $e';
      });
    }
  }

  void forceRefresh() {
    setState(() {
      status = 'loading';
      detailedStatusMessage = 'Loading...';
    });
    checkForUpdates();
  }

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      forceRefresh();
    }

    var appBarActions = [
      IconButton(
        tooltip: "Settings",
        icon: const Icon(Icons.settings),
        onPressed: showSettingsWindow,
      ),
      IconButton(
        tooltip: "Refresh",
        icon: const Icon(Icons.refresh),
        onPressed: forceRefresh,
      ),
      IconButton(
        icon: const Icon(Icons.minimize),
        tooltip: "Close to system tray",
        onPressed: () {
          windowManager.hide();
        },
      ),
      IconButton(
        icon: const Icon(Icons.power_off),
        tooltip: "Quit application",
        onPressed: () {
          windowManager.destroy();
        },
      ),
    ];

    if (status == 'Error') {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Lemmy Notifier'),
          actions: appBarActions,
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
        actions: appBarActions,
        bottom: (status == 'loading' || status == 'checking')
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4.0),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(detailedStatusMessage ?? status ?? ''),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Lemmy Instance: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (siteResponse != null)
                Flexible(
                  child: ClickableLink(
                    linkTitle: siteResponse?.siteView.site.name,
                    linkUrlStr: siteResponse!.siteView.site.actorId,
                  ),
                ),
            ],
          ),
          Center(child: Text('New Posts: ${newPostsCount ?? 'initializing'}')),
          Center(
              child:
                  Text('New Messages: ${newMessagesCount ?? 'initializing'}')),
          const SizedBox(height: 16),
          const Center(
              child: Text(
            "Some New Posts:",
            style: TextStyle(
              decoration: TextDecoration.underline,
            ),
          )),
          for (PostView post in ((posts?.posts ?? [])
              .where((PostView post) => !post.read)
              .toList()))
            Row(
              children: [
                const Text('* '),
                Flexible(
                  child: ClickableLink(
                    linkTitle: post.post.name,
                    linkUrlStr: post.post.apId,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          const Center(
              child: Text(
            "Some Posts with unread comments:",
            style: TextStyle(
              decoration: TextDecoration.underline,
            ),
          )),
          for (PostView post in ((posts?.posts ?? [])
              .where((PostView post) => post.unreadComments > 0)
              .toList()))
            Row(
              children: [
                const Text('* '),
                Flexible(
                  child: ClickableLink(
                    linkTitle: post.post.name,
                    linkUrlStr: post.post.apId,
                  ),
                ),
                Text(' Unread comments: ${post.unreadComments} '),
              ],
            ),
        ],
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
    } else if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'quit') {
      windowManager.destroy();
    }
  }

  void saveSettings(String serverUrl, String username, int timerInterval,
      String? password) async {
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

  @override
  void onWindowBlur() {
    // TODO: implement onWindowBlur
  }

  @override
  void onWindowClose() async {
    bool _isPreventClose = await windowManager.isPreventClose();
    if (_isPreventClose) {
      windowManager.hide();
    }
  }

  @override
  void onWindowDocked() {
    // TODO: implement onWindowDocked
  }

  @override
  void onWindowEnterFullScreen() {
    // TODO: implement onWindowEnterFullScreen
  }

  @override
  void onWindowEvent(String eventName) {
    // TODO: implement onWindowEvent
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  @override
  void onWindowLeaveFullScreen() {
    // TODO: implement onWindowLeaveFullScreen
  }

  @override
  void onWindowMaximize() {
    // TODO: implement onWindowMaximize
  }

  @override
  void onWindowMinimize() {
    // TODO: implement onWindowMinimize
  }

  @override
  void onWindowMove() {
    // TODO: implement onWindowMove
  }

  @override
  void onWindowMoved() {
    // TODO: implement onWindowMoved
  }

  @override
  void onWindowResize() {
    // TODO: implement onWindowResize
  }

  @override
  void onWindowResized() {
    // TODO: implement onWindowResized
  }

  @override
  void onWindowRestore() {
    // TODO: implement onWindowRestore
  }

  @override
  void onWindowUndocked() {
    // TODO: implement onWindowUndocked
  }

  @override
  void onWindowUnmaximize() {
    // TODO: implement onWindowUnmaximize
  }

  @override
  void dispose() {
    updateTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lemmy_notify/settings_page.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
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
        siteResponse = null;
      });
      showSnackbar('Status: $status');

      GetSiteResponse sr = await client.run(GetSite(auth: authResponse?.jwt));
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
    final StreamController<String> eventStreamController =
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
              eventStream: eventStreamController.stream),
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
                eventStreamController.add("save");
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
                  style: const TextStyle(
                      color: Colors.white, decoration: TextDecoration.underline),
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
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('An error occurred:', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(lastError ?? 'Unknown Error', textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: forceRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final newPosts = (posts?.posts ?? []).where((PostView post) => !post.read).toList();
    final unreadComments = (posts?.posts ?? []).where((PostView post) => post.unreadComments > 0).toList();

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Lemmy Notifier'),
        actions: appBarActions,
        elevation: 2,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Instance Info Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.dns, size: 32, color: Colors.blue),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lemmy Instance',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (siteResponse != null)
                          InkWell(
                            onTap: () {
                              launchUrlString(siteResponse!.siteView.site.actorId);
                            },
                            child: Text(
                              siteResponse?.siteView.site.name ?? 'Loading...',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          )
                        else
                          const Text('Connecting...', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stats Row
          Row(
            children: [
              Expanded(
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('New Posts', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          newPostsCount != null ? '$newPostsCount' : '-',
                          style: const TextStyle(fontSize: 24, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('New Messages', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          newMessagesCount != null ? '$newMessagesCount' : '-',
                          style: const TextStyle(fontSize: 24, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // New Posts Section
          if (newPosts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text('New Posts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ...newPosts.map((post) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.article, color: Colors.blue),
                title: Text(post.post.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('by ${post.creator.name}'),
                onTap: () {
                   launchUrlString(post.post.apId);
                },
              ),
            )),
            const SizedBox(height: 16),
          ],

          // Unread Comments Section
          if (unreadComments.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text('Posts with Unread Comments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ...unreadComments.map((post) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.comment, color: Colors.orange),
                title: Text(post.post.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${post.unreadComments} unread comments'),
                onTap: () {
                   launchUrlString(post.post.apId);
                },
              ),
            )),
          ],

          if (newPosts.isEmpty && unreadComments.isEmpty && status == 'updated')
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  'No new updates',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
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

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void onWindowBlur() {
    // TODO: implement onWindowBlur
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
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
    windowManager.removeListener(this);
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SettingsPageSavedResultsFunc = void Function(
    String serverUrl, String username, int timerInterval, String? password);

class SettingsPage extends StatefulWidget {
  final SettingsPageSavedResultsFunc? savedResults;
  final Stream<String> eventStream;

  const SettingsPage(
      {super.key, required this.eventStream, required this.savedResults});

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
      if (mounted) {
        setState(() {
          openMinimizedToSystemTray =
              prefs.getBool('openMinimizedToSystemTray') ??
                  openMinimizedToSystemTray;
          serverController.text = prefs.getString('serverUrl') ?? '';
          usernameController.text = prefs.getString('username') ?? '';
          passwordController.text = '';
          timerIntervalController.text = prefs.getInt('timerInterval') != null
              ? prefs.getInt('timerInterval').toString()
              : '5';
        });
      }
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
              String? pwd;
              if (passwordController.text.isNotEmpty) {
                pwd = passwordController.text;
              }
              // Schedule the callback to run after the build phase
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.savedResults!(
                    serverController.text,
                    usernameController.text,
                    int.tryParse(timerIntervalController.text) ?? 5,
                    pwd);
              });
            }
            // Return a loading indicator or similar while saving
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: serverController,
                  decoration: const InputDecoration(
                    labelText: 'Lemmy Server URL',
                    border: OutlineInputBorder(),
                    hintText: 'https://lemmy.world',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: timerIntervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Timer Interval (minutes)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: openMinimizedToSystemTray,
                  title: const Text('Open minimized to system tray'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool? value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('openMinimizedToSystemTray', value ?? false);
                    if (mounted) {
                      setState(() {
                        openMinimizedToSystemTray = value ?? false;
                      });
                    }
                  },
                ),
              ],
            ),
          );
        });
  }
}

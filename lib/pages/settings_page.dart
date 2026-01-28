import 'dart:async';
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
              widget.savedResults!(
                  serverController.text,
                  usernameController.text,
                  int.parse(timerIntervalController.text),
                  pwd);
            }
          }
          return Column(
            children: [
              TextField(
                controller: serverController,
                decoration:
                    const InputDecoration(labelText: 'Lemmy Server URL'),
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
                  await (await prefs)
                      .setBool('openMinimizedToSystemTray', value ?? false);
                  setState(() {
                    openMinimizedToSystemTray = value ?? false;
                  });
                },
              ),
            ],
          );
        });
  }
}

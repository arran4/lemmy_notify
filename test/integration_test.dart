// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemmy_api_client/v3.dart';

void main() {
  test('Integration test: Connect to active Lemmy instance', () async {
    final serverUrl = Platform.environment['LEMMY_SERVER'];
    final username = Platform.environment['LEMMY_USERNAME'];
    final password = Platform.environment['LEMMY_PASSWORD'];

    if (serverUrl == null || username == null || password == null) {
      print(
          'Skipping integration test: Missing LEMMY_SERVER, LEMMY_USERNAME, or LEMMY_PASSWORD environment variables.');
      return;
    }

    print('Connecting to $serverUrl...');
    final client = LemmyApiV3(serverUrl);

    // Login
    print('Logging in as $username...');
    final authResponse =
        await client.run(Login(usernameOrEmail: username, password: password));
    expect(authResponse.jwt, isNotNull, reason: 'Login failed: JWT is null');
    print('Login successful.');

    // Get Site Info
    print('Fetching site info...');
    final siteResponse = await client.run(GetSite(auth: authResponse.jwt));
    expect(siteResponse.siteView.site.name, isNotNull,
        reason: 'GetSite failed: Site name is null');
    print('Site info fetched: ${siteResponse.siteView.site.name}');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemmy_notify/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    // Mock window_manager
    const MethodChannel windowManagerChannel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'isMinimized') {
        return false;
      }
      if (methodCall.method == 'isPreventClose') {
        return true;
      }
      return null;
    });

    // Mock tray_manager
    const MethodChannel trayManagerChannel = MethodChannel('tray_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayManagerChannel, (MethodCall methodCall) async {
      return null;
    });

    // Mock flutter_secure_storage
    const MethodChannel secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall methodCall) async {
      return null;
    });
  });

  testWidgets('Smoke test: App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    await tester.pumpAndSettle();
  });
}

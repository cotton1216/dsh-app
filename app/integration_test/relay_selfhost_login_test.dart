// Drives the real sign-in form against a self-hosted ds-harness-remote Server,
// so the account path can be exercised on a simulator without typing by hand.
//
//   flutter test integration_test/relay_selfhost_login_test.dart -d <device> \
//     --dart-define=RELAY_SERVER=http://192.168.1.6:8090 \
//     --dart-define=RELAY_ACCOUNT=<email> \
//     --dart-define=RELAY_PASSWORD=<password>
//
// Credentials arrive as dart-defines, never stored in this file or printed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dsh_app/app.dart';
import 'package:dsh_app/main.dart' as app;
import 'package:dsh_app/state/hosts_state.dart';

const _server = String.fromEnvironment('RELAY_SERVER');
const _account = String.fromEnvironment('RELAY_ACCOUNT');
const _password = String.fromEnvironment('RELAY_PASSWORD');

/// Keeps the connected screen on-device so it can be inspected.
const _holdSeconds = int.fromEnvironment('RELAY_HOLD_SEC', defaultValue: 30);

Future<void> _pumpUntil(WidgetTester tester, Finder finder, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 4; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in to a self-hosted relay and connects', (tester) async {
    expect(_server, isNotEmpty, reason: 'pass --dart-define=RELAY_SERVER');
    expect(_account, isNotEmpty, reason: 'pass --dart-define=RELAY_ACCOUNT');
    expect(_password, isNotEmpty, reason: 'pass --dart-define=RELAY_PASSWORD');

    await app.main();
    await _pumpUntil(tester, find.byType(DshApp));
    expect(find.byType(DshApp), findsOneWidget);

    // 1. Remote-host home → self-hosted sign-in sheet.
    await _pumpUntil(tester, find.text('自建服务器 · 邮箱登录'));
    expect(find.text('自建服务器 · 邮箱登录'), findsWidgets, reason: 'self-hosted entry missing');
    await tester.tap(find.text('自建服务器 · 邮箱登录').first);
    await tester.pumpAndSettle();

    // 2. Fill server / account / password.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3), reason: 'expected server, email and password fields');
    await tester.enterText(fields.at(0), _server);
    await tester.enterText(fields.at(1), _account);
    await tester.enterText(fields.at(2), _password);
    await tester.pumpAndSettle();

    // 3. Sign in; the sheet closes on success.
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(TextField).evaluate().isEmpty) break;
    }
    if (find.byType(TextField).evaluate().isNotEmpty) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .where((t) => t.trim().isNotEmpty)
          .toList();
      debugPrint('SHEET_STILL_OPEN_TEXTS: ${texts.join(" | ")}');
    }
    expect(find.byType(TextField), findsNothing, reason: 'sign-in sheet did not close');

    // 4. The account now lists the host; its name is rendered on the home page.
    await _pumpUntil(tester, find.textContaining('XBB-4'), seconds: 40);
    final listed = find.textContaining('XBB-4').evaluate().isNotEmpty;

    final context = tester.element(find.byType(DshApp));
    final container = ProviderScope.containerOf(context);
    final account = container.read(relayAccountProvider).value;
    final hosts = account?.hosts.where((h) => h.online).toList() ?? const [];
    debugPrint('RELAY_LOGIN: signedIn=${account?.signedIn} online=${hosts.length} '
        'listed=$listed names=${hosts.map((h) => h.name).join(",")}');

    expect(account?.signedIn, isTrue, reason: 'account not signed in after login');
    expect(hosts, isNotEmpty, reason: 'no online host after login');

    await Future<void>.delayed(Duration(seconds: _holdSeconds));
  }, timeout: Timeout.none);
}

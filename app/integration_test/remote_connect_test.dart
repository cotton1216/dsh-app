// Drives the real app against a DSH host over SSH, so the whole remote path
// (pinned host key → `dsh web` launched remotely → tunnel) can be exercised on
// a device without tapping the screen by hand.
//
// Run against a booted simulator or a connected phone:
//   flutter test integration_test/remote_connect_test.dart -d <device-id> \
//     --dart-define=DSH_TEST_PRIVKEY_B64=<base64 of the private key> \
//     --dart-define=DSH_TEST_HOST_FP=<SHA256:… of the host key> \
//     [--dart-define=DSH_TEST_HOST=10.0.2.2]
//
// On the Android emulator the host machine is 10.0.2.2, not 127.0.0.1.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dsh_app/app.dart';
import 'package:dsh_app/main.dart' as app;
import 'package:dsh_app/remote/link_status.dart';
import 'package:dsh_app/remote/ssh/ssh_host_config.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';

const _hostId = 'ssh-dshgotest01';
const _privateKeyB64 = String.fromEnvironment('DSH_TEST_PRIVKEY_B64');
const _hostFingerprint = String.fromEnvironment('DSH_TEST_HOST_FP');
const _hostAddr = String.fromEnvironment('DSH_TEST_HOST', defaultValue: '127.0.0.1');

/// How long to keep the connected app alive after the assertions pass, so it
/// can be inspected (or used) from outside before the test tears it down.
const _holdSeconds = int.fromEnvironment('DSH_TEST_HOLD_SEC', defaultValue: 40);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connects to the Mac over SSH', (tester) async {
    expect(_privateKeyB64, isNotEmpty, reason: 'pass --dart-define=DSH_TEST_PRIVKEY_B64');
    expect(_hostFingerprint, isNotEmpty, reason: 'pass --dart-define=DSH_TEST_HOST_FP');

    await app.main();
    for (var i = 0; i < 100 && find.byType(DshApp).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(DshApp), findsOneWidget);

    final context = tester.element(find.byType(DshApp));
    final container = ProviderScope.containerOf(context);
    const host = HostRef.ssh(_hostId);

    final config = SshHostConfig(
      id: _hostId,
      name: '本机 Mac',
      host: _hostAddr,
      port: 22,
      user: 'binny',
      auth: SshAuthMethod.privateKey,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: _hostFingerprint,
    );
    await container.read(hostsProvider.notifier).saveSsh(
          config,
          secrets: SshSecrets(privateKey: utf8.decode(base64.decode(_privateKeyB64))),
        );
    container.read(activeHostProvider.notifier).select(host);

    // Let the screen build its own listeners first: reading a provider while it
    // is still initialising trips Riverpod's "must not modify other providers
    // during build" assertion.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final sub = container.listen(hostLinkStatusProvider(host), (_, __) {});
    addTearDown(sub.close);

    HostLinkStatus? status;
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(seconds: 1));
      status = container.read(hostLinkStatusProvider(host)).value;
      if (status?.phase == HostLinkPhase.connected || status?.phase == HostLinkPhase.failed) break;
    }

    expect(
      status?.phase,
      HostLinkPhase.connected,
      reason: 'phase=${status?.phase} step=${status?.step} '
          'error=${status?.error?.message} detail=${status?.detail}',
    );

    // Let the chat screen settle so the screenshot taken right after shows it.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Hold the connected screen on-device so it can be captured from outside
    // (`xcrun simctl io booted screenshot`) before the test tears the app down.
    await Future<void>.delayed(Duration(seconds: _holdSeconds));
  }, timeout: Timeout.none);
}

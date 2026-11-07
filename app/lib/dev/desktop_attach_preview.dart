// Simulator-only verification entry point. An opt-in owner-only Unix socket
// supplies authorization; no token is compiled into the app or logged.
// Real phones use the SSH attach flow in the normal main.dart entry point.
import 'dart:io';
import 'dart:convert';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../launch/launch_state.dart';
import '../state/locale_state.dart';
import '../state/hosts_state.dart';
import '../state/sessions_state.dart';
import '../state/connection_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var stage = 'authorization';
  try {
    // Simulator has the same OS-user filesystem as its Mac. This socket does
    // not exist on a real phone. It returns credentials only to this OS user.
    final socket = await Socket.connect(InternetAddress(
      '/Users/binny/.xianxingtong/phone-pairing/host.sock',
      type: InternetAddressType.unix), 0);
    final pairing = jsonDecode(await utf8.decoder.bind(socket).join()) as Map<String, dynamic>;
    socket.destroy();
    final value = pairing['url'] as String;
    final uri = parseAttachUrl(value);
    if (uri == null) throw StateError('Desktop authorization required');
    stage = 'HTTP and mux';
    final client = await DshClient.connect(
      baseUri: uri.replace(query: ''),
      token: uri.queryParameters['token'],
    );
    stage = 'session list';
    final sessions = await client.listSessions();
    final count = sessions.length;
    debugPrint('DESKTOP_ATTACH: authenticated, mux ready, sessions=$count');
    stage = 'native UI';
    await Future.wait([AppLanguageController.load(), LaunchController.begin()]);
    final container = ProviderContainer(overrides: [
      activeConnectionProvider.overrideWith((ref) => AsyncData(HostConnection(
        client: client, isLocal: false, kind: HostKind.ssh,
        hostId: 'desktop-preview', name: '如意 · 同一后端',
      ))),
    ]);
    await container.read(hostsProvider.notifier).ready;
    container.read(activeHostProvider.notifier).select(const HostRef.ssh('desktop-preview'));
    runApp(UncontrolledProviderScope(container: container, child: const DshApp()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final verification = sessions.where((session) => session.title == '手机双端连接验证').firstOrNull;
      if (verification != null) container.read(currentSessionProvider.notifier).select(verification.sessionId);
    });
  } catch (error) {
    // Never stringify connection exceptions: they can carry request URLs.
    debugPrint('DESKTOP_ATTACH: failed (${error.runtimeType})');
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('连接未完成：$stage (${error.runtimeType})')))));
  }
}

// Talks to the running desktop through its opt-in owner-only pairing socket.
// No credentials or conversation text are logged or written to disk.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dsh_client/dsh_client.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME']!;
  final socket = await Socket.connect(InternetAddress('$home/.xianxingtong/phone-pairing/host.sock', type: InternetAddressType.unix), 0);
  final text = await utf8.decoder.bind(socket).join();
  socket.destroy();
  final pairing = jsonDecode(text) as Map<String, dynamic>;
  final uri = Uri.parse(pairing['url'] as String);
  final a = await DshClient.connect(baseUri: uri.replace(query: ''), token: uri.queryParameters['token']);
  try {
    final b = await DshClient.connect(baseUri: uri.replace(query: ''), token: uri.queryParameters['token']);
    try {
      final left = await a.listSessions();
      final right = await b.listSessions();
      if (left.length != right.length) throw StateError('Client lists differ');
      stdout.writeln('PASS authenticated HTTP + two live mux clients; hostPid=${pairing['pid']}; sessions=${left.length}');
      if (args.contains('--verify-result')) {
        final session = left.firstWhere((s) => s.title == '手机双端连接验证');
        final snapshot = await a.watch(session.sessionId).where((e) => e is SessionSnapshotEvent).cast<SessionSnapshotEvent>().first.timeout(const Duration(seconds: 15));
        final turns = snapshot.events.whereType<TurnEndedEvent>();
        stdout.writeln('VERIFY_RESULT: turns=${turns.length}; completed=${turns.isNotEmpty && turns.last.reason.isCompleted}; assistantMessages=${snapshot.events.whereType<AssistantMessageEvent>().length}');
      }
      if (args.contains('--prompt')) {
        final created = await a.createSession();
        await a.renameSession(created.sessionId, '手机双端连接验证');
        final ready = Completer<void>();
        final finished = Completer<void>();
        var sawUser = false;
        var sawAssistant = false;
        final subscription = b.watch(created.sessionId).listen((event) {
          if (event is SessionSnapshotEvent && !ready.isCompleted) ready.complete();
          if (event is UserMessageEvent) sawUser = true;
          if (event is AssistantMessageEvent) sawAssistant = true;
          if (event is TurnEndedEvent && !finished.isCompleted) finished.complete();
        }, onError: (Object error) {
          if (!finished.isCompleted) finished.completeError(StateError('Watch failed: ${error.runtimeType}'));
        });
        try {
          await ready.future.timeout(const Duration(seconds: 15));
          await a.prompt(created.sessionId, '这是手机双端连接验证。请不要调用任何工具，只回复：双端连接成功。');
          await finished.future.timeout(const Duration(seconds: 90));
          stdout.writeln('SECOND_CLIENT: user_event=$sawUser assistant_event=$sawAssistant');
          if (!sawUser || !sawAssistant) throw StateError('Missing cross-client events');
        } finally { await subscription.cancel(); }
      }
    } finally { await b.close(); }
  } finally { await a.close(); }
}

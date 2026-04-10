import 'dart:async';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';

const _tickRate = 30; // Hz
const _tickInterval = Duration(milliseconds: 1000 ~/ _tickRate); // ~33ms

Handler buildCanvasHandler() {
  var nextClientId = 1;
  final clients = <int, WebSocketChannel>{};

  // Events accumulated since last tick — flushed every 33ms
  final worldState = <(int, CanvasMessage)>[];

  // Full history — sent to new clients on connect
  final history = <(int, CanvasMessage)>[];

  Timer.periodic(_tickInterval, (_) {
    if (worldState.isEmpty || clients.isEmpty) return;

    final frame = encodeWorldState(worldState);
    for (final client in clients.values) {
      client.sink.add(frame);
    }

    print('[tick] ${worldState.length} events → ${clients.length} clients');
    worldState.clear();
  });

  return webSocketHandler((WebSocketChannel client) {
    final clientId = nextClientId++;
    clients[clientId] = client;
    print('[+] Client $clientId connected. Total: ${clients.length}');

    // Replay full history to the new client immediately
    if (history.isNotEmpty) {
      print('[history] Replaying ${history.length} events to new client $clientId');
      client.sink.add(encodeWorldState(history));
    }

    client.stream.listen(
      (data) {
        if (data is! Uint8List) {
          client.sink.close(4000, 'Binary only');
          return;
        }

        final message = CanvasMessage.decode(data);
        if (message == null) return;

        worldState.add((clientId, message));
        history.add((clientId, message)); // persist for future joiners
      },
      onDone: () {
        clients.remove(clientId);
        print('[-] Client $clientId disconnected. Total: ${clients.length}');
      },
      onError: (error) {
        clients.remove(clientId);
        print('[!] Client $clientId error: $error');
      },
    );
  });
}

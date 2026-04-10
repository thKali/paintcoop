import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';
import '../services/douglas_peucker.dart';

const _tickInterval = Duration(milliseconds: 1000 ~/ 30); // 30Hz
const _compressInterval = Duration(minutes: 2);
const _compressEpsilon = 2.5; // pixels — lower = more precise, higher = more compressed
const _historyCap = 10000; // hard ceiling before compression kicks in

class Room {
  final String code;
  final bool isPrivate;
  final DateTime createdAt;

  var _nextClientId = 1;
  final clients = <int, WebSocketChannel>{};
  final worldState = <(int, CanvasMessage)>[];
  final history = <(int, CanvasMessage)>[];

  DateTime? lastEmptyAt;

  late final Timer _ticker;
  late final Timer _compressor;

  Room({required this.code, required this.isPrivate})
      : createdAt = DateTime.now(),
        lastEmptyAt = DateTime.now() {
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
    _compressor = Timer.periodic(_compressInterval, (_) => _compress());
  }

  int get clientCount => clients.length;
  bool get isEmpty => clients.isEmpty;

  void _tick() {
    if (worldState.isEmpty || clients.isEmpty) return;

    final frame = encodeWorldState(worldState);
    for (final client in clients.values) {
      client.sink.add(frame);
    }
    worldState.clear();
  }

  // Groups history into strokes, runs Douglas-Peucker on each, re-flattens
  void _compress() {
    if (history.length < 100) return;

    final before = history.length;

    // Split into strokes by penDown markers
    final strokes = <List<(int, CanvasMessage)>>[];
    for (final entry in history) {
      if (entry.$2.type == MessageType.penDown) {
        strokes.add([entry]);
      } else if (strokes.isNotEmpty) {
        strokes.last.add(entry);
      }
    }

    // Compress draw points within each stroke
    final compressed = <(int, CanvasMessage)>[];
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      final senderId = stroke.first.$1;
      final draws = stroke.skip(1).map((e) => e.$2).toList();

      compressed.add(stroke.first); // keep penDown

      if (draws.length < 3) {
        compressed.addAll(draws.map((m) => (senderId, m)));
      } else {
        compressed.addAll(
          douglasPeucker(draws, _compressEpsilon, (m) => m.x, (m) => m.y)
              .map((m) => (senderId, m)),
        );
      }
    }

    history
      ..clear()
      ..addAll(compressed);

    print('[compress] room $code: $before → ${history.length} events');
  }

  int addClient(WebSocketChannel client) {
    final clientId = _nextClientId++;
    clients[clientId] = client;
    lastEmptyAt = null;

    if (history.isNotEmpty) {
      client.sink.add(encodeWorldState(history));
    }

    return clientId;
  }

  void removeClient(int clientId) {
    clients.remove(clientId);
    if (clients.isEmpty) {
      lastEmptyAt = DateTime.now();
    }
  }

  void receive(int clientId, CanvasMessage message) {
    worldState.add((clientId, message));
    history.add((clientId, message));

    // Hard cap — compress immediately if we hit the ceiling
    if (history.length >= _historyCap) _compress();
  }

  void dispose() {
    _ticker.cancel();
    _compressor.cancel();
    for (final client in clients.values) {
      client.sink.close();
    }
    clients.clear();
  }
}

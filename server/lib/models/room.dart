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

  // Groups history into strokes, runs Douglas-Peucker on each, re-flattens.
  // Non-stroke events (erase, clear) are passed through unchanged.
  void _compress() {
    if (history.length < 100) return;

    final before = history.length;
    final compressed = <(int, CanvasMessage)>[];
    var currentStroke = <(int, CanvasMessage)>[];

    void flushStroke() {
      if (currentStroke.isEmpty) return;
      final senderId = currentStroke.first.$1;
      final draws = currentStroke.skip(1).map((e) => e.$2).toList();
      compressed.add(currentStroke.first); // penDown
      if (draws.length < 3) {
        compressed.addAll(draws.map((m) => (senderId, m)));
      } else {
        compressed.addAll(
          douglasPeucker(draws, _compressEpsilon, (m) => m.x, (m) => m.y)
              .map((m) => (senderId, m)),
        );
      }
      currentStroke.clear();
    }

    for (final entry in history) {
      switch (entry.$2.type) {
        case MessageType.penDown:
          flushStroke();
          currentStroke.add(entry);
        case MessageType.draw:
          if (currentStroke.isNotEmpty) currentStroke.add(entry);
        case MessageType.erase:
        case MessageType.clear:
          flushStroke();
          compressed.add(entry);
        case MessageType.cursor:
        case MessageType.join:
        case MessageType.leave:
          break; // ephemeral, drop
      }
    }
    flushStroke();

    history
      ..clear()
      ..addAll(compressed);

    print('[compress] room $code: $before → ${history.length} events');
  }

  void _broadcastNow(List<(int, CanvasMessage)> events) {
    if (events.isEmpty || clients.isEmpty) return;
    final frame = encodeWorldState(events);
    for (final client in clients.values) {
      client.sink.add(frame);
    }
  }

  int addClient(WebSocketChannel client) {
    final clientId = _nextClientId++;
    clients[clientId] = client;
    lastEmptyAt = null;

    if (history.isNotEmpty) {
      client.sink.add(encodeWorldState(history));
    }

    _broadcastNow([(clientId, CanvasMessage(type: MessageType.join, x: clientCount.toDouble(), y: 0))]);

    return clientId;
  }

  void removeClient(int clientId) {
    clients.remove(clientId);
    if (clients.isEmpty) {
      lastEmptyAt = DateTime.now();
    }
    _broadcastNow([(clientId, CanvasMessage(type: MessageType.leave, x: clientCount.toDouble(), y: 0))]);
  }

  void receive(int clientId, CanvasMessage message) {
    worldState.add((clientId, message));
    // Cursor events are ephemeral — no need to replay them to new clients
    if (message.type != MessageType.cursor) {
      history.add((clientId, message));
    }

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

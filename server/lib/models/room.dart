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

  final clients = <WebSocketChannel>{};
  final worldState = <CanvasMessage>[];
  final history = <CanvasMessage>[];

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
    for (final client in clients) {
      client.sink.add(frame);
    }
    worldState.clear();
  }

  // Groups history into strokes, runs Douglas-Peucker on each, re-flattens
  void _compress() {
    if (history.length < 100) return;

    final before = history.length;

    // Split into strokes by penDown markers
    final strokes = <List<CanvasMessage>>[];
    for (final msg in history) {
      if (msg.type == MessageType.penDown) {
        strokes.add([msg]); // start new stroke with the penDown event
      } else if (strokes.isNotEmpty) {
        strokes.last.add(msg);
      }
    }

    // Compress draw points within each stroke
    final compressed = <CanvasMessage>[];
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      final penDown = stroke.first; // keep the penDown marker
      final draws = stroke.skip(1).toList();

      compressed.add(penDown);

      if (draws.length < 3) {
        compressed.addAll(draws);
      } else {
        compressed.addAll(douglasPeucker(
          draws,
          _compressEpsilon,
          (m) => m.x,
          (m) => m.y,
        ));
      }
    }

    history
      ..clear()
      ..addAll(compressed);

    print('[compress] room $code: $before → ${history.length} events');
  }

  void addClient(WebSocketChannel client) {
    clients.add(client);
    lastEmptyAt = null;

    if (history.isNotEmpty) {
      client.sink.add(encodeWorldState(history));
    }
  }

  void removeClient(WebSocketChannel client) {
    clients.remove(client);
    if (clients.isEmpty) {
      lastEmptyAt = DateTime.now();
    }
  }

  void receive(CanvasMessage message) {
    worldState.add(message);
    history.add(message);

    // Hard cap — compress immediately if we hit the ceiling
    if (history.length >= _historyCap) _compress();
  }

  void dispose() {
    _ticker.cancel();
    _compressor.cancel();
    for (final client in clients) {
      client.sink.close();
    }
    clients.clear();
  }
}

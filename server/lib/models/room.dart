import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';
import '../services/douglas_peucker.dart';

const _tickInterval = Duration(milliseconds: 1000 ~/ 30); // 30Hz
const _compressInterval = Duration(minutes: 2);
const _compressEpsilon = 2.5; // pixels — lower = more precise, higher = more compressed
const _historyCap = 10000; // hard ceiling before compression kicks in
const _historyTarget = 4000; // target after compression+trim — ensures headroom before next cap hit

class Room {
  final String code;
  final bool isPrivate;
  final DateTime createdAt;

  var _nextClientId = 1;
  final clients = <int, WebSocketChannel>{};
  final worldState = <(int, CanvasMessage)>[];
  final history = <(int, CanvasMessage)>[];

  DateTime? lastEmptyAt;
  DateTime? _lastCapCompress;

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

  Map<String, dynamic> get stats => {
    'code': code,
    'private': isPrivate,
    'clients': clientCount,
    'historyEvents': history.length,
    'historyBytes': history.length * 11, // 11 bytes per event (wire format)
    'worldStateEvents': worldState.length,
    'historyCap': _historyCap,
    'historyTarget': _historyTarget,
    'createdAt': createdAt.toIso8601String(),
    'lastEmptyAt': lastEmptyAt?.toIso8601String(),
    'lastCapCompress': _lastCapCompress?.toIso8601String(),
  };

  void _tick() {
    if (worldState.isEmpty || clients.isEmpty) return;

    final frame = encodeWorldState(worldState);
    for (final client in clients.values) {
      client.sink.add(frame);
    }
    worldState.clear();
  }

  // Simulates the canvas state (same logic as the client), baking in erases
  // and clears so dead draw events are removed. Then runs Douglas-Peucker on
  // the surviving strokes and re-flattens into events.
  void _compress() {
    if (history.length < 100) return;

    final before = history.length;

    // Ordered list of strokes as they'd appear on the canvas (preserves layering).
    final strokes = <(int, List<CanvasMessage>)>[];
    // senderId → index of the currently-open stroke in [strokes].
    final openIdx = <int, int>{};
    const eraseR2 = 20.0 * 20.0;

    for (final (senderId, msg) in history) {
      switch (msg.type) {
        case MessageType.penDown:
          openIdx[senderId] = strokes.length;
          strokes.add((senderId, []));
        case MessageType.draw:
          final i = openIdx[senderId];
          if (i != null) strokes[i].$2.add(msg);
        case MessageType.erase:
          // Bake the erase circle into the stroke data: split surviving segments,
          // drop points inside the circle. Erase events themselves are consumed.
          final next = <(int, List<CanvasMessage>)>[];
          for (final stroke in strokes) {
            if (stroke.$1 != senderId) { next.add(stroke); continue; }
            var seg = <CanvasMessage>[];
            for (final pt in stroke.$2) {
              final dx = pt.x - msg.x, dy = pt.y - msg.y;
              if (dx * dx + dy * dy > eraseR2) {
                seg.add(pt);
              } else if (seg.isNotEmpty) {
                next.add((senderId, seg));
                seg = [];
              }
            }
            if (seg.isNotEmpty) next.add((senderId, seg));
          }
          strokes..clear()..addAll(next);
          // Re-sync indices — erase may shift positions for all senders.
          openIdx.clear();
          for (var i = 0; i < strokes.length; i++) { openIdx[strokes[i].$1] = i; }
        case MessageType.clear:
          // Sender clears only their own strokes.
          strokes.removeWhere((s) => s.$1 == senderId);
          openIdx.remove(senderId);
          // Re-sync indices for remaining senders.
          openIdx.clear();
          for (var i = 0; i < strokes.length; i++) { openIdx[strokes[i].$1] = i; }
        case MessageType.cursor:
        case MessageType.join:
        case MessageType.leave:
          break; // ephemeral, drop
      }
    }

    // Convert surviving strokes back to events, applying DP.
    const penDownMsg = CanvasMessage(type: MessageType.penDown, x: 0, y: 0);
    final compressed = <(int, CanvasMessage)>[];
    for (final (senderId, points) in strokes) {
      if (points.isEmpty) continue;
      compressed.add((senderId, penDownMsg));
      final reduced = points.length < 3
          ? points
          : douglasPeucker(points, _compressEpsilon, (m) => m.x, (m) => m.y);
      compressed.addAll(reduced.map((m) => (senderId, m)));
    }

    history
      ..clear()
      ..addAll(compressed);

    // If DP barely helped (already-compressed strokes dominate), trim the
    // oldest complete strokes to restore headroom. Without this, the cap gets
    // hit on every event and compression runs O(n) continuously.
    if (history.length > _historyTarget) {
      _trimToTarget(_historyTarget);
    }

    print('[compress] room $code: $before → ${history.length} events (after trim)');
  }

  // Removes oldest complete strokes (and standalone erase/clear events) until
  // history.length <= target. Cuts on penDown/erase/clear boundaries so we
  // never leave orphaned draw events without a preceding penDown.
  void _trimToTarget(int target) {
    final excess = history.length - target;
    // Scan forward to find a clean cut point past `excess` entries.
    // We stop at the next penDown/erase/clear so we don't strand draw events.
    var cutAt = excess;
    while (cutAt < history.length) {
      final type = history[cutAt].$2.type;
      if (type == MessageType.penDown ||
          type == MessageType.erase ||
          type == MessageType.clear) { break; }
      cutAt++;
    }
    if (cutAt > 0 && cutAt <= history.length) {
      history.removeRange(0, cutAt);
    }
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

    // Hard cap — compress when ceiling is hit, but at most once per interval
    // to avoid O(n) compression on every event when the board is very full.
    if (history.length >= _historyCap) {
      final now = DateTime.now();
      if (_lastCapCompress == null ||
          now.difference(_lastCapCompress!) >= _compressInterval) {
        _lastCapCompress = now;
        _compress();
      }
    }
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

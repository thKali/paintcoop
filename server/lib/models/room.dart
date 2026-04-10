import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';
import '../services/douglas_peucker.dart';

const _tickInterval = Duration(milliseconds: 1000 ~/ 30); // 30Hz
const _compressInterval = Duration(minutes: 2);
const _compressEpsilon = 2.5; // pixels — lower = more precise, higher = more compressed

class Room {
  final String code;
  final bool isPrivate;
  final DateTime createdAt;

  var _nextClientId = 1;
  final clients = <int, WebSocketChannel>{};
  final worldState = <(int, CanvasMessage)>[];
  final history = <(int, CanvasMessage)>[];

  DateTime? lastEmptyAt;
  // Debounce timers for per-sender erase flush (keyed by clientId)
  final _eraseFlush = <int, Timer>{};

  late final Timer _ticker;
  late final Timer _compressor;

  Room({required this.code, required this.isPrivate})
      : createdAt = DateTime.now(),
        lastEmptyAt = DateTime.now() {
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
    _compressor = Timer.periodic(_compressInterval, (_) {}); // compression disabled
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
    'createdAt': createdAt.toIso8601String(),
    'lastEmptyAt': lastEmptyAt?.toIso8601String(),
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

    switch (message.type) {
      case MessageType.cursor:
        break; // ephemeral, not stored
      case MessageType.clear:
        // Remove all of this sender's draw history immediately — no need to
        // store the clear event itself since the absence of draws is enough.
        history.removeWhere((e) =>
            e.$1 == clientId &&
            (e.$2.type == MessageType.penDown ||
                e.$2.type == MessageType.draw ||
                e.$2.type == MessageType.erase));
      case MessageType.erase:
        // Store the event so it's available for the debounced flush below.
        history.add((clientId, message));
        // Debounce: flush erase geometry 1s after the last erase from this sender.
        _eraseFlush[clientId]?.cancel();
        _eraseFlush[clientId] = Timer(
          const Duration(seconds: 1),
          () => _flushErase(clientId),
        );
      default:
        history.add((clientId, message));
    }

  }

  // Applies all pending erase events for [clientId] geometrically to history,
  // then removes the erase events themselves. Called 1s after last erase.
  void _flushErase(int clientId) {
    _eraseFlush.remove(clientId);
    const eraseR2 = 20.0 * 20.0;

    // Collect erase circles for this sender
    final circles = history
        .where((e) => e.$1 == clientId && e.$2.type == MessageType.erase)
        .map((e) => (e.$2.x, e.$2.y))
        .toList();

    if (circles.isEmpty) return;

    // Rebuild history: apply all erase circles to this sender's strokes
    final next = <(int, CanvasMessage)>[];
    var seg = <CanvasMessage>[];
    int? segSender;

    void flushSeg() {
      if (seg.isNotEmpty && segSender != null) {
        next.add((segSender!, const CanvasMessage(type: MessageType.penDown, x: 0, y: 0)));
        next.addAll(seg.map((m) => (segSender!, m)));
        seg = [];
        segSender = null;
      }
    }

    for (final (sender, msg) in history) {
      if (sender != clientId) {
        flushSeg();
        next.add((sender, msg));
        continue;
      }
      switch (msg.type) {
        case MessageType.erase:
          break; // consumed
        case MessageType.penDown:
          flushSeg();
          segSender = sender;
        case MessageType.draw:
          if (segSender != null) {
            final erased = circles.any((c) {
              final dx = msg.x - c.$1, dy = msg.y - c.$2;
              return dx * dx + dy * dy <= eraseR2;
            });
            if (erased) {
              flushSeg(); // emit what we have, then start a new segment
              segSender = sender; // continue collecting remaining points
            } else {
              seg.add(msg);
            }
          }
        default:
          flushSeg();
          next.add((sender, msg));
      }
    }
    flushSeg();

    history
      ..clear()
      ..addAll(next);
  }

  void dispose() {
    _ticker.cancel();
    _compressor.cancel();
    for (final t in _eraseFlush.values) { t.cancel(); }
    _eraseFlush.clear();
    for (final client in clients.values) {
      client.sink.close();
    }
    clients.clear();
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import '../config.dart';
import '../protocol/message.dart';
import '../services/room_manager.dart';

// Tracks how many rooms each IP created within the sliding window
final _ipCreations = <String, List<DateTime>>{};

Router buildRouter() {
  final router = Router();

  router.post('/rooms', (Request req) async {
    final ip = _clientIp(req);

    if (!_allowCreation(ip)) {
      return Response(429,
          body: 'Too many rooms created. Try again later.',
          headers: _corsHeaders);
    }

    // Reject oversized bodies before reading
    final contentLength = int.tryParse(
          req.headers['content-length'] ?? '',
        ) ??
        0;
    if (contentLength > ServerConfig.maxBodyBytes) {
      return Response(413, body: 'Request body too large.', headers: _corsHeaders);
    }

    final rawBody = await req.readAsString();
    if (rawBody.length > ServerConfig.maxBodyBytes) {
      return Response(413, body: 'Request body too large.', headers: _corsHeaders);
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(rawBody) as Map<String, dynamic>;
    } on FormatException {
      return Response(400, body: 'Invalid JSON.', headers: _corsHeaders);
    }

    final isPrivate = body['private'] as bool? ?? false;
    final room = RoomManager.instance.create(isPrivate: isPrivate);

    _recordCreation(ip);

    return _json({'code': room.code, 'private': room.isPrivate});
  });

  router.get('/rooms', (Request req) {
    final rooms = RoomManager.instance.publicRooms().map((r) => {
          'code': r.code,
          'clientCount': r.clientCount,
          'createdAt': r.createdAt.toIso8601String(),
        }).toList();
    return _json(rooms);
  });

  router.get('/ws/<code>', (Request req, String code) {
    final room = RoomManager.instance.find(code);
    if (room == null) {
      return webSocketHandler((channel) {
        channel.sink.close(4004, 'Room not found');
      })(req);
    }

    if (room.clientCount >= ServerConfig.maxClientsPerRoom) {
      return Response(503, body: 'Room is full.', headers: _corsHeaders);
    }

    final wsHandler = webSocketHandler((channel) {
      final clientId = room.addClient(channel);
      print('[+] Client $clientId joined room $code. Total: ${room.clientCount}');

      var messageCount = 0;
      var windowStart = DateTime.now();

      channel.stream.listen(
        (data) {
          // Throttle — reset counter every second
          final now = DateTime.now();
          if (now.difference(windowStart).inSeconds >= 1) {
            messageCount = 0;
            windowStart = now;
          }
          messageCount++;

          if (messageCount > ServerConfig.maxMessagesPerSecond) {
            return; // drop message silently, don't kill the connection
          }

          if (data is! Uint8List) {
            channel.sink.close(4000, 'Binary only');
            return;
          }

          final message = CanvasMessage.decode(data);
          if (message == null) return;

          room.receive(clientId, message);
        },
        onDone: () {
          room.removeClient(clientId);
          print('[-] Client $clientId left room $code. Total: ${room.clientCount}');
        },
        onError: (_) => room.removeClient(clientId),
      );
    });

    return wsHandler(req);
  });

  return router;
}

// Extract real client IP, respecting reverse-proxy header
String _clientIp(Request req) =>
    req.headers['x-forwarded-for']?.split(',').first.trim() ??
    req.headers['x-real-ip'] ??
    'unknown';

// Returns true if this IP is within the creation limit
bool _allowCreation(String ip) {
  _pruneWindow(ip);
  final count = _ipCreations[ip]?.length ?? 0;
  return count < ServerConfig.maxRoomsPerIp;
}

void _recordCreation(String ip) {
  _ipCreations.putIfAbsent(ip, () => []).add(DateTime.now());
}

// Remove timestamps outside the sliding window
void _pruneWindow(String ip) {
  final cutoff = DateTime.now().subtract(ServerConfig.roomCreationWindow);
  _ipCreations[ip]?.removeWhere((t) => t.isBefore(cutoff));
}

Response _json(Object data) => Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json', ..._corsHeaders},
    );

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

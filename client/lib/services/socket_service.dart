import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';

class SocketService {
  final String _url;

  WebSocketChannel? _channel;
  final _incomingController = StreamController<List<CanvasMessage>>.broadcast();
  final _fatalController = StreamController<String>.broadcast();

  Timer? _reconnectTimer;
  int _reconnectDelaySecs = 1;
  bool _disposed = false;

  SocketService(this._url);

  // The UI listens to this — receives a batch of messages every tick
  Stream<List<CanvasMessage>> get incoming => _incomingController.stream;

  // Emits a reason string on unrecoverable errors (e.g. 'room_not_found')
  Stream<String> get fatalErrors => _fatalController.stream;

  void connect() {
    if (_disposed) return;

    _channel = WebSocketChannel.connect(Uri.parse(_url));

    _channel!.stream.listen(
      (data) {
        _reconnectDelaySecs = 1; // reset backoff on successful data
        if (data is! Uint8List) return;

        final messages = decodeWorldState(data);
        if (messages.isEmpty) return;

        print('[<] Received tick: ${messages.length} events');
        _incomingController.add(messages);
      },
      onDone: () {
        final closeCode = _channel?.closeCode;
        if (closeCode == 4004) {
          print('[socket] Room not found (4004), giving up.');
          _fatalController.add('room_not_found');
          return;
        }
        print('[socket] Disconnected, reconnecting in ${_reconnectDelaySecs}s...');
        _scheduleReconnect();
      },
      onError: (e) {
        print('[socket] Error: $e, reconnecting in ${_reconnectDelaySecs}s...');
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySecs), () {
      _reconnectDelaySecs = (_reconnectDelaySecs * 2).clamp(1, 30);
      connect();
    });
  }

  void sendPenDown() {
    // x and y are irrelevant for penDown, just need the type byte
    final message = CanvasMessage(type: MessageType.penDown, x: 0, y: 0);
    _channel?.sink.add(message.encode());
  }

  void sendDraw(double x, double y) {
    final message = CanvasMessage(type: MessageType.draw, x: x, y: y);
    _channel?.sink.add(message.encode());
  }

  void sendCursor(double x, double y) {
    final message = CanvasMessage(type: MessageType.cursor, x: x, y: y);
    _channel?.sink.add(message.encode());
  }

  void sendErase(double x, double y) {
    final message = CanvasMessage(type: MessageType.erase, x: x, y: y);
    _channel?.sink.add(message.encode());
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _incomingController.close();
    _fatalController.close();
  }
}

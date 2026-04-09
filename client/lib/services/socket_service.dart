import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/message.dart';

class SocketService {
  final String _url;

  WebSocketChannel? _channel;
  final _incomingController = StreamController<List<CanvasMessage>>.broadcast();

  SocketService(this._url);

  // The UI listens to this — receives a batch of messages every tick
  Stream<List<CanvasMessage>> get incoming => _incomingController.stream;

  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(_url));

    _channel!.stream.listen(
      (data) {
        if (data is! Uint8List) return;

        final messages = decodeWorldState(data);
        if (messages.isEmpty) return;

        print('[<] Received tick: ${messages.length} events');
        _incomingController.add(messages);
      },
      onDone: () => print('[socket] Disconnected'),
      onError: (e) => print('[socket] Error: $e'),
    );
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

  void disconnect() {
    _channel?.sink.close();
    _incomingController.close();
  }
}

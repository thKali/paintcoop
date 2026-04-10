import 'dart:typed_data';

enum MessageType {
  draw(0x01),
  cursor(0x02),
  clear(0x03),
  penDown(0x04), // marks the start of a new stroke
  erase(0x05); // eraser drag — (x, y) = center of eraser circle

  final int byte;
  const MessageType(this.byte);

  static MessageType? fromByte(int byte) {
    return MessageType.values.where((t) => t.byte == byte).firstOrNull;
  }
}

class CanvasMessage {
  final MessageType type;
  final double x;
  final double y;

  const CanvasMessage({required this.type, required this.x, required this.y});

  // Decode a single 9-byte frame from a client
  // Layout: [type(1)] [x float32(4)] [y float32(4)]
  static CanvasMessage? decode(Uint8List bytes) {
    if (bytes.length < 9) return null;

    final view = ByteData.sublistView(bytes);
    final typeByte = view.getUint8(0);
    final type = MessageType.fromByte(typeByte);

    if (type == null) return null;

    final x = view.getFloat32(1, Endian.big);
    final y = view.getFloat32(5, Endian.big);

    return CanvasMessage(type: type, x: x, y: y);
  }

  // Encode a single message into 11 bytes (clientId + type + x + y)
  void encodeTo(ByteData view, int offset, int clientId) {
    view.setUint16(offset, clientId, Endian.big);
    view.setUint8(offset + 2, type.byte);
    view.setFloat32(offset + 3, x, Endian.big);
    view.setFloat32(offset + 7, y, Endian.big);
  }

  @override
  String toString() => 'CanvasMessage(type: $type, x: $x, y: $y)';
}

// Serializes a list of (clientId, message) pairs into a broadcast frame:
// Layout: [count uint16(2)] [clientId uint16(2) + type(1) + x float32(4) + y float32(4)] * N
// = 11 bytes per message
Uint8List encodeWorldState(List<(int, CanvasMessage)> messages) {
  final totalBytes = 2 + messages.length * 11;
  final view = ByteData(totalBytes);

  view.setUint16(0, messages.length, Endian.big);

  for (var i = 0; i < messages.length; i++) {
    final (clientId, msg) = messages[i];
    msg.encodeTo(view, 2 + i * 11, clientId);
  }

  return view.buffer.asUint8List();
}

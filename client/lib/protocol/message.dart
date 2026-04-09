import 'dart:typed_data';

enum MessageType {
  draw(0x01),
  cursor(0x02),
  clear(0x03),
  penDown(0x04); // marks the start of a new stroke

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

  // Encode a single event to send to the server
  // Layout: [type(1)] [x float32(4)] [y float32(4)]
  Uint8List encode() {
    final view = ByteData(9);
    view.setUint8(0, type.byte);
    view.setFloat32(1, x, Endian.big);
    view.setFloat32(5, y, Endian.big);
    return view.buffer.asUint8List();
  }
}

// Decode a broadcast frame from the server
// Layout: [count uint16(2)] [msg1(9)] [msg2(9)] ... [msgN(9)]
List<CanvasMessage> decodeWorldState(Uint8List bytes) {
  if (bytes.length < 2) return [];

  final view = ByteData.sublistView(bytes);
  final count = view.getUint16(0, Endian.big);

  final messages = <CanvasMessage>[];

  for (var i = 0; i < count; i++) {
    final offset = 2 + i * 9;
    if (offset + 9 > bytes.length) break;

    final typeByte = view.getUint8(offset);
    final type = MessageType.fromByte(typeByte);
    if (type == null) continue;

    final x = view.getFloat32(offset + 1, Endian.big);
    final y = view.getFloat32(offset + 5, Endian.big);

    messages.add(CanvasMessage(type: type, x: x, y: y));
  }

  return messages;
}

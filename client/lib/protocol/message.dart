import 'dart:typed_data';

enum MessageType {
  draw(0x01),
  cursor(0x02),
  clear(0x03),
  penDown(0x04), // marks the start of a new stroke
  erase(0x05), // eraser drag — (x, y) = center of eraser circle
  join(0x06), // player joined — x = new total player count
  leave(0x07); // player left — x = new total player count

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
  final int senderId; // set by decodeWorldState; 0 for locally sent messages

  const CanvasMessage({required this.type, required this.x, required this.y, this.senderId = 0});

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
// Layout: [count uint16(2)] [clientId uint16(2) + type(1) + x float32(4) + y float32(4)] * N
// = 11 bytes per message
List<CanvasMessage> decodeWorldState(Uint8List bytes) {
  if (bytes.length < 2) return [];

  final view = ByteData.sublistView(bytes);
  final count = view.getUint16(0, Endian.big);

  final messages = <CanvasMessage>[];

  for (var i = 0; i < count; i++) {
    final offset = 2 + i * 11;
    if (offset + 11 > bytes.length) break;

    final senderId = view.getUint16(offset, Endian.big);
    final typeByte = view.getUint8(offset + 2);
    final type = MessageType.fromByte(typeByte);
    if (type == null) continue;

    final x = view.getFloat32(offset + 3, Endian.big);
    final y = view.getFloat32(offset + 7, Endian.big);

    messages.add(CanvasMessage(type: type, x: x, y: y, senderId: senderId));
  }

  return messages;
}

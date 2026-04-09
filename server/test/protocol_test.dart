import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:server/protocol/message.dart';

// Mirrors what the Flutter client does to encode a single message
class ByteDataHelper {
  static Uint8List encode(CanvasMessage msg) {
    final view = ByteData(9);
    view.setUint8(0, msg.type.byte);
    view.setFloat32(1, msg.x, Endian.big);
    view.setFloat32(5, msg.y, Endian.big);
    return view.buffer.asUint8List();
  }
}

void main() {
  group('CanvasMessage encode/decode round-trip', () {
    test('draw message preserves type, x, y', () {
      const original = CanvasMessage(type: MessageType.draw, x: 120.5, y: 87.3);
      final decoded = CanvasMessage.decode(ByteDataHelper.encode(original));

      expect(decoded, isNotNull);
      expect(decoded!.type, MessageType.draw);
      expect(decoded.x, closeTo(120.5, 0.001));
      expect(decoded.y, closeTo(87.3, 0.001));
    });

    test('penDown message round-trips correctly', () {
      const original = CanvasMessage(type: MessageType.penDown, x: 0, y: 0);
      final decoded = CanvasMessage.decode(ByteDataHelper.encode(original));
      expect(decoded!.type, MessageType.penDown);
    });

    test('cursor message round-trips correctly', () {
      const original = CanvasMessage(type: MessageType.cursor, x: 999.9, y: 1.1);
      final decoded = CanvasMessage.decode(ByteDataHelper.encode(original));
      expect(decoded!.type, MessageType.cursor);
      expect(decoded.x, closeTo(999.9, 0.01));
      expect(decoded.y, closeTo(1.1, 0.001));
    });

    test('produces exactly 9 bytes', () {
      const msg = CanvasMessage(type: MessageType.draw, x: 1.0, y: 2.0);
      expect(ByteDataHelper.encode(msg).length, 9);
    });

    test('returns null for buffers shorter than 9 bytes', () {
      expect(CanvasMessage.decode(Uint8List(5)), isNull);
    });

    test('returns null for unknown message type byte', () {
      final bytes = Uint8List(9);
      bytes[0] = 0xFF;
      expect(CanvasMessage.decode(bytes), isNull);
    });

    test('extreme coordinate values survive round-trip', () {
      const msg = CanvasMessage(type: MessageType.draw, x: 7680.0, y: 4320.0);
      final decoded = CanvasMessage.decode(ByteDataHelper.encode(msg));
      expect(decoded!.x, closeTo(7680.0, 0.1));
      expect(decoded.y, closeTo(4320.0, 0.1));
    });
  });

  group('encodeWorldState', () {
    test('empty list produces 2-byte frame', () {
      expect(encodeWorldState([]).length, 2);
    });

    test('count header matches number of messages', () {
      final messages = [
        const CanvasMessage(type: MessageType.draw, x: 1, y: 2),
        const CanvasMessage(type: MessageType.draw, x: 3, y: 4),
        const CanvasMessage(type: MessageType.penDown, x: 0, y: 0),
      ];
      final frame = encodeWorldState(messages);
      final count = ByteData.sublistView(frame).getUint16(0, Endian.big);

      expect(count, 3);
      expect(frame.length, 2 + 3 * 9);
    });

    test('all messages survive world state round-trip', () {
      final messages = [
        const CanvasMessage(type: MessageType.penDown, x: 0, y: 0),
        const CanvasMessage(type: MessageType.draw, x: 10.0, y: 20.0),
        const CanvasMessage(type: MessageType.draw, x: 30.0, y: 40.0),
      ];

      final frame = encodeWorldState(messages);
      final view = ByteData.sublistView(frame);
      final count = view.getUint16(0, Endian.big);

      final decoded = [
        for (var i = 0; i < count; i++)
          CanvasMessage.decode(frame.sublist(2 + i * 9, 2 + (i + 1) * 9))!,
      ];

      expect(decoded[0].type, MessageType.penDown);
      expect(decoded[1].x, closeTo(10.0, 0.001));
      expect(decoded[2].y, closeTo(40.0, 0.001));
    });
  });
}

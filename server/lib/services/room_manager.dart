import 'dart:async';
import 'dart:math';
import '../models/room.dart';

const _emptyTtl = Duration(minutes: 5);
const _cleanupInterval = Duration(minutes: 1);

class RoomManager {
  static final RoomManager instance = RoomManager._();

  RoomManager._() {
    // Check every minute for rooms that have been empty too long
    Timer.periodic(_cleanupInterval, (_) => _cleanup());
  }

  final _rooms = <String, Room>{};
  final _random = Random();

  Room create({required bool isPrivate}) {
    final code = _generateCode();
    final room = Room(code: code, isPrivate: isPrivate);
    _rooms[code] = room;
    print('[room] Created ${isPrivate ? 'private' : 'public'} room: $code');
    return room;
  }

  Room? find(String code) => _rooms[code.toUpperCase()];

  List<Room> publicRooms() =>
      _rooms.values.where((r) => !r.isPrivate).toList();

  void _cleanup() {
    final now = DateTime.now();
    final expired = <String>[];

    for (final entry in _rooms.entries) {
      final room = entry.value;
      final emptyAt = room.lastEmptyAt;

      if (emptyAt != null && now.difference(emptyAt) >= _emptyTtl) {
        expired.add(entry.key);
      }
    }

    for (final code in expired) {
      _rooms[code]?.dispose();
      _rooms.remove(code);
      print('[room] Removed expired room: $code');
    }

    if (expired.isNotEmpty) {
      print('[room] Cleanup: removed ${expired.length} room(s). Active: ${_rooms.length}');
    }
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    String code;
    do {
      code = List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
    } while (_rooms.containsKey(code));
    return code;
  }
}

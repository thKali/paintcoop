import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/room.dart';

class ApiService {
  static final instance = ApiService._();
  ApiService._();

  Future<String> createRoom({required bool isPrivate}) async {
    final res = await http.post(
      Uri.parse('${Config.apiUrl}/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'private': isPrivate}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['code'] as String;
  }

  Future<List<Room>> listRooms() async {
    final res = await http.get(Uri.parse('${Config.apiUrl}/rooms'));
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }
}

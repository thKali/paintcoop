import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:server/handlers/room_handler.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(logRequests())
      .addHandler(buildRouter().call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server running on http://${server.address.host}:${server.port}');
}

// Allow requests from the Flutter web app (localhost:*)
Middleware _cors() => (Handler inner) => (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: _corsHeaders);
    };

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

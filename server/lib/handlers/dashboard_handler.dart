import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import '../config.dart';
import '../models/room.dart';
import '../services/room_manager.dart';

final String _dashboardSecret = () {
  final secret = Platform.environment['DASHBOARD_SECRET'];
  if (secret != null && secret.isNotEmpty) return secret;
  final generated = _randomSecret();
  print('[dashboard] No DASHBOARD_SECRET set — using generated key: $generated');
  return generated;
}();

String _randomSecret() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = Random.secure();
  return List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
}

Response buildDashboardResponse(Request req) {
  final authHeader = req.headers['authorization'] ?? '';
  if (!_checkBasicAuth(authHeader)) {
    return Response(401, headers: {
      'WWW-Authenticate': 'Basic realm="paintcoop dashboard"',
      'Content-Type': 'text/plain',
    }, body: 'Unauthorized');
  }

  final rooms = RoomManager.instance.allRooms()
    ..sort((a, b) => b.history.length.compareTo(a.history.length));

  final now = DateTime.now();
  final totalClients = rooms.fold(0, (s, r) => s + r.clientCount);
  final totalEvents = rooms.fold(0, (s, r) => s + r.history.length);
  final totalBytes = totalEvents * 11;

  final rows = rooms.map((r) => _roomRow(r, now)).join('\n');

  final html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="refresh" content="5">
  <title>paintcoop dashboard</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: monospace; background: #0d0d0d; color: #e0e0e0; padding: 24px; }
    h1 { font-size: 1.1rem; color: #aaa; margin-bottom: 16px; }
    .summary { display: flex; gap: 32px; margin-bottom: 24px; flex-wrap: wrap; }
    .stat { background: #1a1a1a; border: 1px solid #2a2a2a; border-radius: 6px; padding: 12px 20px; }
    .stat-label { font-size: 0.7rem; color: #666; text-transform: uppercase; letter-spacing: 1px; }
    .stat-value { font-size: 1.4rem; color: #fff; margin-top: 4px; }
    table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
    th { text-align: left; padding: 8px 12px; color: #555; font-weight: normal;
         border-bottom: 1px solid #222; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 1px; }
    td { padding: 8px 12px; border-bottom: 1px solid #1a1a1a; vertical-align: middle; }
    tr:hover td { background: #161616; }
    .code { color: #7eb8f7; font-weight: bold; }
    .bar-wrap { background: #1a1a1a; border-radius: 3px; height: 6px; width: 120px; overflow: hidden; display: inline-block; vertical-align: middle; margin-left: 8px; }
    .bar { height: 100%; border-radius: 3px; background: #4a9eff; }
    .bar.warn { background: #f0a000; }
    .bar.crit { background: #e04040; }
    .tag { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 0.7rem; }
    .tag-priv { background: #2a1a2a; color: #c080c0; }
    .tag-pub  { background: #1a2a1a; color: #60b060; }
    .empty { color: #444; }
    .ts { color: #555; font-size: 0.75rem; }
    footer { margin-top: 24px; color: #333; font-size: 0.72rem; }
  </style>
</head>
<body>
  <h1>paintcoop &mdash; dashboard &nbsp;<span class="ts">auto-refresh 5s &nbsp;&bull;&nbsp; ${_fmt(now)}</span></h1>

  <div class="summary">
    <div class="stat"><div class="stat-label">Rooms</div><div class="stat-value">${rooms.length}</div></div>
    <div class="stat"><div class="stat-label">Clients online</div><div class="stat-value">$totalClients</div></div>
    <div class="stat"><div class="stat-label">Total history events</div><div class="stat-value">${_fmtNum(totalEvents)}</div></div>
    <div class="stat"><div class="stat-label">History memory</div><div class="stat-value">${_fmtBytes(totalBytes)}</div></div>
    <div class="stat"><div class="stat-label">Cap / target</div><div class="stat-value">${_fmtNum(ServerConfig.maxClientsPerRoom)} clients</div></div>
  </div>

  ${rooms.isEmpty ? '<p class="empty">No active rooms.</p>' : '''
  <table>
    <thead>
      <tr>
        <th>Room</th>
        <th>Type</th>
        <th>Clients</th>
        <th>History events</th>
        <th>History memory</th>
        <th>World state</th>
        <th>Last compress</th>
        <th>Age</th>
        <th>Empty since</th>
      </tr>
    </thead>
    <tbody>
$rows
    </tbody>
  </table>'''}

  <footer>history cap: ${_fmtNum(_historyCap)} &bull; target after compress: ${_fmtNum(_historyTarget)} &bull; 11 bytes/event</footer>
</body>
</html>''';

  return Response.ok(html, headers: {'Content-Type': 'text/html; charset=utf-8'});
}

bool _checkBasicAuth(String header) {
  if (!header.startsWith('Basic ')) return false;
  final decoded = utf8.decode(base64.decode(header.substring(6)));
  // Accept any username, check only the password
  final password = decoded.contains(':') ? decoded.split(':').skip(1).join(':') : decoded;
  return password == _dashboardSecret;
}

String _roomRow(Room r, DateTime now) {
  final pct = r.history.length / _historyCap;
  final barClass = pct > 0.85 ? 'crit' : pct > 0.6 ? 'warn' : '';
  final barWidth = (pct * 100).clamp(0, 100).toStringAsFixed(1);
  final typeTag = r.isPrivate
      ? '<span class="tag tag-priv">private</span>'
      : '<span class="tag tag-pub">public</span>';
  final lastCompress = r.stats['lastCapCompress'] as String?;
  final emptyAt = r.lastEmptyAt;
  final age = _ago(r.createdAt, now);

  return '''      <tr>
        <td class="code">${r.code}</td>
        <td>$typeTag</td>
        <td>${r.clientCount} / ${ServerConfig.maxClientsPerRoom}</td>
        <td>
          ${_fmtNum(r.history.length)} / ${_fmtNum(_historyCap)}
          <span class="bar-wrap"><span class="bar $barClass" style="width:$barWidth%"></span></span>
        </td>
        <td>${_fmtBytes(r.history.length * 11)}</td>
        <td>${r.worldState.length} events</td>
        <td class="ts">${lastCompress != null ? '${_ago(DateTime.parse(lastCompress), now)} ago' : '&mdash;'}</td>
        <td class="ts">$age ago</td>
        <td class="ts">${emptyAt != null ? '${_ago(emptyAt, now)} ago' : 'occupied'}</td>
      </tr>''';
}

String _ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

String _fmt(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

String _fmtNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

// Expose constants from room.dart for the footer
const _historyCap = 10000;
const _historyTarget = 4000;

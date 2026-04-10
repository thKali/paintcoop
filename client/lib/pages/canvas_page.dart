import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../config.dart';
import '../protocol/message.dart';
import '../services/socket_service.dart';

class CanvasPage extends StatefulWidget {
  final String roomCode;

  const CanvasPage({super.key, required this.roomCode});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  late final SocketService _socket;
  final List<(int senderId, List<Offset> points)> _strokes = [];
  bool _codeVisible = false;
  Offset? _erasePosition;

  static const _eraseRadius = 20.0;

  @override
  void initState() {
    super.initState();
    _socket = SocketService('${Config.wsUrl}/ws/${widget.roomCode}');
    _socket.connect();

    _socket.fatalErrors.listen((reason) {
      if (!mounted) return;
      if (reason == 'room_not_found') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room not found.')),
        );
        context.go('/');
      }
    });

    _socket.incoming.listen((messages) {
      setState(() {
        for (final msg in messages) {
          if (msg.type == MessageType.penDown) {
            _strokes.add((msg.senderId, []));
          } else if (msg.type == MessageType.draw) {
            final idx = _strokes.lastIndexWhere((s) => s.$1 == msg.senderId);
            if (idx >= 0) _strokes[idx].$2.add(Offset(msg.x, msg.y));
          } else if (msg.type == MessageType.erase) {
            _applyErase(msg.senderId, msg.x, msg.y);
          }
        }
      });
    });
  }

  void _applyErase(int senderId, double cx, double cy) {
    const r2 = _eraseRadius * _eraseRadius;
    final result = <(int, List<Offset>)>[];

    for (final stroke in _strokes) {
      if (stroke.$1 != senderId) {
        result.add(stroke);
        continue;
      }

      // Split the stroke into segments that lie outside the eraser circle
      var segment = <Offset>[];
      for (final pt in stroke.$2) {
        final dx = pt.dx - cx;
        final dy = pt.dy - cy;
        if (dx * dx + dy * dy > r2) {
          segment.add(pt);
        } else if (segment.isNotEmpty) {
          result.add((senderId, segment));
          segment = [];
        }
      }
      if (segment.isNotEmpty) result.add((senderId, segment));
    }

    _strokes
      ..clear()
      ..addAll(result);
  }

  @override
  void dispose() {
    _socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Canvas
          Listener(
            onPointerDown: (e) {
              if (e.buttons == kSecondaryMouseButton) {
                BrowserContextMenu.disableContextMenu();
                setState(() => _erasePosition = e.localPosition);
                _socket.sendErase(e.localPosition.dx, e.localPosition.dy);
              }
            },
            onPointerMove: (e) {
              if (e.buttons == kSecondaryMouseButton) {
                setState(() => _erasePosition = e.localPosition);
                _socket.sendErase(e.localPosition.dx, e.localPosition.dy);
              }
            },
            onPointerUp: (e) {
              if (_erasePosition != null) {
                BrowserContextMenu.enableContextMenu();
                setState(() => _erasePosition = null);
              }
            },
            child: GestureDetector(
              onPanStart: (_) => _socket.sendPenDown(),
              onPanUpdate: (d) => _socket.sendDraw(d.localPosition.dx, d.localPosition.dy),
              child: CustomPaint(
                foregroundPainter: CanvasPainter(
                  strokes: _strokes,
                  erasePosition: _erasePosition,
                ),
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),

          // Room code overlay — top right
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: _RoomCodeBadge(
              code: widget.roomCode,
              visible: _codeVisible,
              onToggleVisibility: () =>
                  setState(() => _codeVisible = !_codeVisible),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeBadge extends StatelessWidget {
  final String code;
  final bool visible;
  final VoidCallback onToggleVisibility;

  const _RoomCodeBadge({
    required this.code,
    required this.visible,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Copy share link button
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Copy invite link',
            onPressed: () {
              final shareUrl = Uri.base
                  .replace(path: '/room/$code', queryParameters: {}, fragment: '')
                  .toString();
              Clipboard.setData(ClipboardData(text: shareUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invite link copied!'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 8),

          // Code — blurred or visible
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: visible
                ? Text(
                    code,
                    key: const ValueKey('visible'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  )
                : ImageFiltered(
                    key: const ValueKey('blurred'),
                    imageFilter: _blurFilter,
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 8),

          // Visibility toggle
          IconButton(
            icon: Icon(
              visible ? Icons.visibility_off : Icons.visibility,
              size: 16,
              color: Colors.white70,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: visible ? 'Hide code' : 'Show code',
            onPressed: onToggleVisibility,
          ),
        ],
      ),
    );
  }
}

// Blur amount for the hidden code
final _blurFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);

// Cache so paint() doesn't allocate a new Color object per stroke per frame.
final _senderColors = <int, Color>{};

Color _colorForSender(int senderId) => _senderColors.putIfAbsent(senderId, () {
      final hue = (senderId * 137.508) % 360;
      return HSLColor.fromAHSL(1.0, hue, 0.75, 0.62).toColor();
    });

class CanvasPainter extends CustomPainter {
  final List<(int senderId, List<Offset> points)> strokes;
  final Offset? erasePosition;

  CanvasPainter({required this.strokes, this.erasePosition});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final (senderId, points) in strokes) {
      if (points.length < 2) continue;
      paint.color = _colorForSender(senderId);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (erasePosition != null) {
      canvas.drawCircle(
        erasePosition!,
        _CanvasPageState._eraseRadius,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) => true;
}

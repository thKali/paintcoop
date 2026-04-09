import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<List<Offset>> _strokes = [];
  bool _codeVisible = false;

  @override
  void initState() {
    super.initState();
    _socket = SocketService('${Config.wsUrl}/ws/${widget.roomCode}');
    _socket.connect();

    _socket.incoming.listen((messages) {
      setState(() {
        for (final msg in messages) {
          if (msg.type == MessageType.penDown) {
            _strokes.add([]);
          } else if (msg.type == MessageType.draw && _strokes.isNotEmpty) {
            _strokes.last.add(Offset(msg.x, msg.y));
          }
        }
      });
    });
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
          GestureDetector(
            onPanStart: (_) => _socket.sendPenDown(),
            onPanUpdate: (d) => _socket.sendDraw(d.localPosition.dx, d.localPosition.dy),
            child: CustomPaint(
              foregroundPainter: CanvasPainter(strokes: _strokes),
              child: Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
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
                  .replace(path: '/room/$code', queryParameters: {})
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

class CanvasPainter extends CustomPainter {
  final List<List<Offset>> strokes;

  CanvasPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) => true;
}

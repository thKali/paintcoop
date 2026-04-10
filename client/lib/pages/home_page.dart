// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config.dart';
import '../models/room.dart';
import '../services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _codeController = TextEditingController();
  List<Room> _publicRooms = [];
  bool _loadingRooms = false;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (_router != router) {
      _router?.routerDelegate.removeListener(_onRouteChange);
      _router = router;
      _router!.routerDelegate.addListener(_onRouteChange);
    }
  }

  void _onRouteChange() {
    if (!mounted) return;
    final path = _router?.routerDelegate.currentConfiguration.uri.path;
    if (path == '/') _loadRooms();
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChange);
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() => _loadingRooms = true);
    try {
      final rooms = await ApiService.instance.listRooms();
      setState(() => _publicRooms = rooms);
    } finally {
      setState(() => _loadingRooms = false);
    }
  }

  Future<void> _createRoom({required bool isPrivate}) async {
    final code = await ApiService.instance.createRoom(isPrivate: isPrivate);
    if (!mounted) return;
    _enterRoom(code);
  }

  void _joinRoom() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room code must be 6 characters')),
      );
      return;
    }
    _enterRoom(code);
  }

  void _enterRoom(String code) {
    context.go('/room/$code');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('paintcoop'),
      ),
      body: Stack(children: [
        Padding(
        padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Join by code
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: 'Enter room code',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _joinRoom(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _joinRoom,
                  child: const Text('Join'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Create room buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _createRoom(isPrivate: false),
                    child: const Text('Create Public Room'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _createRoom(isPrivate: true),
                    child: const Text('Create Private Room'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Public rooms list
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Public Rooms',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadRooms,
                  tooltip: 'Refresh',
                ),
              ],
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _loadingRooms
                  ? const Center(child: CircularProgressIndicator())
                  : _publicRooms.isEmpty
                      ? const Center(
                          child: Text('No public rooms yet.',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.separated(
                          itemCount: _publicRooms.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final room = _publicRooms[i];
                            return ListTile(
                              title: Text(room.code,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${room.clientCount} ${room.clientCount == 1 ? 'person' : 'people'} drawing'),
                              trailing: const Icon(Icons.arrow_forward_ios,
                                  size: 16),
                              onTap: () => _enterRoom(room.code),
                            );
                          },
                        ),
            ),
          ],
        ),
        ),
        Positioned(
          bottom: 12,
          right: 16,
          child: GestureDetector(
            onTap: () => html.window.open('${Config.apiUrl}/dashboard', '_blank'),
            child: const Text('·',
                style: TextStyle(color: Color(0xFF2A2A2A), fontSize: 28)),
          ),
        ),
      ]),
    );
  }
}

abstract final class ServerConfig {
  /// Max rooms a single IP can create within [roomCreationWindow]
  static const maxRoomsPerIp = 5;
  static const roomCreationWindow = Duration(minutes: 10);

  /// Max concurrent WebSocket clients per room
  static const maxClientsPerRoom = 20;

  /// Max WebSocket messages per second per client before being kicked
  static const maxMessagesPerSecond = 1000;

  /// Max HTTP request body size in bytes (1 KB is plenty for our JSON)
  static const maxBodyBytes = 1024;
}

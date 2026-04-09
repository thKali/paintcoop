class Room {
  final String code;
  final int clientCount;
  final DateTime createdAt;

  const Room({
    required this.code,
    required this.clientCount,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        code: json['code'] as String,
        clientCount: json['clientCount'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

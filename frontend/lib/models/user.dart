class User {
  User({
    required this.id,
    required this.username,
    required this.nickname,
    this.email,
    this.createdAt,
  });

  final int id;
  final String username;
  final String nickname;
  final String? email;
  final String? createdAt;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      email: json['email'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'email': email,
        'createdAt': createdAt,
      };
}

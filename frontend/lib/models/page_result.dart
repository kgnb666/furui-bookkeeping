class PageResult<T> {
  PageResult({
    required this.total,
    required this.page,
    required this.size,
    required this.list,
  });

  final int total;
  final int page;
  final int size;
  final List<T> list;

  bool get hasMore => page * size < total;

  factory PageResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) mapper) {
    final rawList = (json['list'] as List<dynamic>? ?? []);
    return PageResult<T>(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? rawList.length,
      list: rawList.map((item) => mapper(item as Map<String, dynamic>)).toList(),
    );
  }
}

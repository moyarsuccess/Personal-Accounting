class Category {
  final String id;
  final String name;
  final String iconCode;
  final int colorCode;

  Category({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconCode': iconCode,
      'colorCode': colorCode,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      iconCode: map['iconCode'],
      colorCode: map['colorCode'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

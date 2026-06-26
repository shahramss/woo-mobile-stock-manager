class ProductCategory {
  ProductCategory({
    required this.id,
    required this.name,
    required this.count,
  });

  final int id;
  final String name;
  final int count;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      count: int.tryParse((json['count'] ?? '0').toString()) ?? 0,
    );
  }
}

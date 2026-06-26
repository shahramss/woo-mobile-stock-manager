class Product {
  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.regularPrice,
    required this.stockQuantity,
    required this.stockStatus,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final String price;
  final String regularPrice;
  final int? stockQuantity;
  final String stockStatus;
  final String imageUrl;

  bool get isInStock => stockStatus == 'instock';

  Product copyWith({
    String? regularPrice,
    int? stockQuantity,
    String? stockStatus,
    String? imageUrl,
  }) {
    return Product(
      id: id,
      name: name,
      price: price,
      regularPrice: regularPrice ?? this.regularPrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      stockStatus: stockStatus ?? this.stockStatus,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      regularPrice: (json['regular_price'] ?? '').toString(),
      stockQuantity: json['stock_quantity'] == null
          ? null
          : int.tryParse(json['stock_quantity'].toString()),
      stockStatus: (json['stock_status'] ?? 'outofstock').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
    );
  }
}

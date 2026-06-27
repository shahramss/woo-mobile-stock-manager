class Product {
  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.regularPrice,
    required this.stockQuantity,
    required this.stockStatus,
    required this.imageUrl,
    required this.baleCooldownRemaining,
    required this.lastAction,
    required this.lastActionAt,
    required this.updatedActionAt,
    required this.baleSentActionAt,
  });

  final int id;
  final String name;
  final String price;
  final String regularPrice;
  final int? stockQuantity;
  final String stockStatus;
  final String imageUrl;
  final int baleCooldownRemaining;
  final String lastAction;
  final String lastActionAt;
  final String updatedActionAt;
  final String baleSentActionAt;

  bool get isInStock => stockStatus == 'instock';
  bool _isRecent(String value) {
    if (value.isEmpty) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    return !diff.isNegative && diff.inHours < 24;
  }

  bool get hasRecentAction => wasUpdatedRecent || wasSentToBaleRecent;

  // اگر محصول در ۲۴ ساعت اخیر بروزرسانی شده باشد.
  bool get wasUpdatedRecent => _isRecent(updatedActionAt) || (lastAction == 'updated' && _isRecent(lastActionAt));

  // اگر محصول در ۲۴ ساعت اخیر به بله ارسال شده باشد.
  bool get wasSentToBaleRecent => _isRecent(baleSentActionAt) || (lastAction == 'bale_sent' && _isRecent(lastActionAt));

  bool get hasBothRecentActions => wasUpdatedRecent && wasSentToBaleRecent;

  bool get wasUpdatedLast => wasUpdatedRecent;
  bool get wasSentToBaleLast => wasSentToBaleRecent;

  Product copyWith({
    String? regularPrice,
    int? stockQuantity,
    String? stockStatus,
    String? imageUrl,
    int? baleCooldownRemaining,
    String? lastAction,
    String? lastActionAt,
    String? updatedActionAt,
    String? baleSentActionAt,
  }) {
    return Product(
      id: id,
      name: name,
      price: price,
      regularPrice: regularPrice ?? this.regularPrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      stockStatus: stockStatus ?? this.stockStatus,
      imageUrl: imageUrl ?? this.imageUrl,
      baleCooldownRemaining: baleCooldownRemaining ?? this.baleCooldownRemaining,
      lastAction: lastAction ?? this.lastAction,
      lastActionAt: lastActionAt ?? this.lastActionAt,
      updatedActionAt: updatedActionAt ?? this.updatedActionAt,
      baleSentActionAt: baleSentActionAt ?? this.baleSentActionAt,
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
      baleCooldownRemaining: int.tryParse((json['bale_cooldown_remaining'] ?? '0').toString()) ?? 0,
      lastAction: (json['last_action'] ?? '').toString(),
      lastActionAt: (json['last_action_at'] ?? '').toString(),
      updatedActionAt: (json['updated_action_at'] ?? '').toString(),
      baleSentActionAt: (json['bale_sent_action_at'] ?? '').toString(),
    );
  }
}

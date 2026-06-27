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
    required this.actionState,
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

  /// حالت رنگ محصول که از افزونه وردپرس می‌آید:
  /// none / updated / bale_sent / both
  final String actionState;

  bool get isInStock => stockStatus == 'instock';

  bool _isRecent(String value) {
    if (value.isEmpty) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    return !diff.isNegative && diff.inHours < 24;
  }

  bool get wasUpdatedRecent {
    if (actionState == 'updated' || actionState == 'both') return true;
    return _isRecent(updatedActionAt) || (lastAction == 'updated' && _isRecent(lastActionAt));
  }

  bool get wasSentToBaleRecent {
    if (actionState == 'bale_sent' || actionState == 'both') return true;
    return _isRecent(baleSentActionAt) || (lastAction == 'bale_sent' && _isRecent(lastActionAt));
  }

  bool get hasBothRecentActions => actionState == 'both' || (wasUpdatedRecent && wasSentToBaleRecent);
  bool get hasRecentAction => hasBothRecentActions || wasUpdatedRecent || wasSentToBaleRecent;

  bool get wasUpdatedLast => wasUpdatedRecent;
  bool get wasSentToBaleLast => wasSentToBaleRecent;

  Product copyWith({
    String? regularPrice,
    Object? stockQuantity = _sentinel,
    String? stockStatus,
    String? imageUrl,
    int? baleCooldownRemaining,
    String? lastAction,
    String? lastActionAt,
    String? updatedActionAt,
    String? baleSentActionAt,
    String? actionState,
  }) {
    return Product(
      id: id,
      name: name,
      price: price,
      regularPrice: regularPrice ?? this.regularPrice,
      stockQuantity: stockQuantity == _sentinel ? this.stockQuantity : stockQuantity as int?,
      stockStatus: stockStatus ?? this.stockStatus,
      imageUrl: imageUrl ?? this.imageUrl,
      baleCooldownRemaining: baleCooldownRemaining ?? this.baleCooldownRemaining,
      lastAction: lastAction ?? this.lastAction,
      lastActionAt: lastActionAt ?? this.lastActionAt,
      updatedActionAt: updatedActionAt ?? this.updatedActionAt,
      baleSentActionAt: baleSentActionAt ?? this.baleSentActionAt,
      actionState: actionState ?? this.actionState,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final updatedAt = (json['updated_action_at'] ?? '').toString();
    final baleAt = (json['bale_sent_action_at'] ?? '').toString();
    var state = (json['action_state'] ?? '').toString();
    if (state.isEmpty) {
      // پشتیبانی از نسخه‌های قدیمی‌تر افزونه
      final temp = Product(
        id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
        name: (json['name'] ?? '').toString(),
        price: (json['price'] ?? '').toString(),
        regularPrice: (json['regular_price'] ?? '').toString(),
        stockQuantity: json['stock_quantity'] == null ? null : int.tryParse(json['stock_quantity'].toString()),
        stockStatus: (json['stock_status'] ?? 'outofstock').toString(),
        imageUrl: (json['image_url'] ?? '').toString(),
        baleCooldownRemaining: int.tryParse((json['bale_cooldown_remaining'] ?? '0').toString()) ?? 0,
        lastAction: (json['last_action'] ?? '').toString(),
        lastActionAt: (json['last_action_at'] ?? '').toString(),
        updatedActionAt: updatedAt,
        baleSentActionAt: baleAt,
        actionState: 'none',
      );
      if (temp.wasUpdatedRecent && temp.wasSentToBaleRecent) {
        state = 'both';
      } else if (temp.wasUpdatedRecent) {
        state = 'updated';
      } else if (temp.wasSentToBaleRecent) {
        state = 'bale_sent';
      } else {
        state = 'none';
      }
    }

    return Product(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      regularPrice: (json['regular_price'] ?? '').toString(),
      stockQuantity: json['stock_quantity'] == null ? null : int.tryParse(json['stock_quantity'].toString()),
      stockStatus: (json['stock_status'] ?? 'outofstock').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      baleCooldownRemaining: int.tryParse((json['bale_cooldown_remaining'] ?? '0').toString()) ?? 0,
      lastAction: (json['last_action'] ?? '').toString(),
      lastActionAt: (json['last_action_at'] ?? '').toString(),
      updatedActionAt: updatedAt,
      baleSentActionAt: baleAt,
      actionState: state,
    );
  }
}

const Object _sentinel = Object();

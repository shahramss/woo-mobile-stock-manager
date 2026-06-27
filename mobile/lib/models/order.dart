class OrderPage {
  OrderPage({required this.items, required this.page, required this.totalPages});
  final List<OrderSummary> items;
  final int page;
  final int totalPages;
  bool get hasMore => page < totalPages;
}

class OrderSummary {
  OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.statusLabel,
    required this.dateCreated,
    required this.total,
    required this.paymentMethodTitle,
    required this.customerName,
    required this.phone,
  });

  final int id;
  final String number;
  final String status;
  final String statusLabel;
  final String dateCreated;
  final String total;
  final String paymentMethodTitle;
  final String customerName;
  final String phone;

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      number: (json['number'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusLabel: (json['status_label'] ?? '').toString(),
      dateCreated: (json['date_created'] ?? '').toString(),
      total: (json['total'] ?? '').toString(),
      paymentMethodTitle: (json['payment_method_title'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
    );
  }
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.number,
    required this.status,
    required this.statusLabel,
    required this.dateCreated,
    required this.total,
    required this.shippingTotal,
    required this.paymentMethodTitle,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.postcode,
    required this.items,
  });

  final int id;
  final String number;
  final String status;
  final String statusLabel;
  final String dateCreated;
  final String total;
  final String shippingTotal;
  final String paymentMethodTitle;
  final String customerName;
  final String phone;
  final String address;
  final String postcode;
  final List<OrderItem> items;

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return OrderDetail(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      number: (json['number'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusLabel: (json['status_label'] ?? '').toString(),
      dateCreated: (json['date_created'] ?? '').toString(),
      total: (json['total'] ?? '').toString(),
      shippingTotal: (json['shipping_total'] ?? '').toString(),
      paymentMethodTitle: (json['payment_method_title'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      postcode: (json['postcode'] ?? '').toString(),
      items: rawItems.whereType<Map<String, dynamic>>().map(OrderItem.fromJson).toList(),
    );
  }
}

class OrderItem {
  OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
    required this.price,
    required this.imageUrl,
  });

  final int productId;
  final String name;
  final int quantity;
  final String total;
  final String price;
  final String imageUrl;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: int.tryParse((json['product_id'] ?? '0').toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      quantity: int.tryParse((json['quantity'] ?? '0').toString()) ?? 0,
      total: (json['total'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
    );
  }
}

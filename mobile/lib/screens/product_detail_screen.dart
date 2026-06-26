import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId, required this.productName});

  final int productId;
  final String productName;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();

  Product? _product;
  bool _loading = true;
  bool _saving = false;
  bool _inStock = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final product = await api.getProduct(widget.productId);
      _product = product;
      _priceController.text = product.regularPrice;
      _stockController.text = (product.stockQuantity ?? 0).toString();
      _inStock = product.isInStock;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'جزئیات محصول دریافت نشد.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _product == null) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      final api = context.read<AuthProvider>().api;
      final updated = await api.updateProduct(
        id: widget.productId,
        regularPrice: _normalizeNumber(_priceController.text),
        stockQuantity: int.parse(_normalizeNumber(_stockController.text)),
        stockStatus: _inStock ? 'instock' : 'outofstock',
      );

      setState(() => _product = updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تغییرات ذخیره شد')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ذخیره تغییرات انجام نشد.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _normalizeNumber(String input) {
    const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var text = input.trim().replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_product?.name ?? widget.productName)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 90),
          EmptyState(message: _error!, icon: Icons.error_outline),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _loadProduct, child: const Text('تلاش دوباره')),
        ],
      );
    }

    final product = _product!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProductHeader(product: product),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'قیمت',
                        suffixText: 'تومان',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      validator: (value) {
                        final text = _normalizeNumber(value ?? '');
                        if (text.isEmpty) return 'قیمت را وارد کنید.';
                        final number = double.tryParse(text);
                        if (number == null || number < 0) return 'قیمت معتبر نیست.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'تعداد موجودی انبار',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) {
                        final text = _normalizeNumber(value ?? '');
                        if (text.isEmpty) return 'تعداد انبار را وارد کنید.';
                        final number = int.tryParse(text);
                        if (number == null || number < 0) return 'تعداد انبار معتبر نیست.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'وضعیت موجودی',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(_inStock ? 'موجود' : 'ناموجود'),
                          const SizedBox(width: 8),
                          Switch(
                            value: _inStock,
                            onChanged: (value) => setState(() => _inStock = value),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تغییرات'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 88,
                height: 88,
                color: const Color(0xFFEFF6FF),
                child: product.imageUrl.isEmpty
                    ? const Icon(Icons.image_outlined, color: Color(0xFF2563EB), size: 34)
                    : Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFF2563EB), size: 34),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('نام محصول', style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.isInStock ? 'موجود' : 'ناموجود',
                    style: TextStyle(
                      color: product.isInStock ? const Color(0xFF166534) : const Color(0xFF991B1B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';
import 'bale_settings_screen.dart';

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
  final _baleTextController = TextEditingController();

  Product? _product;
  Timer? _cooldownTimer;
  bool _loading = true;
  bool _saving = false;
  bool _sendingToBale = false;
  bool _uploadingImage = false;
  bool _inStock = true;
  bool _hasChanged = false;
  int _baleCooldown = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _priceController.dispose();
    _stockController.dispose();
    _baleTextController.dispose();
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
      _stockController.text = (product.stockQuantity == null || product.stockQuantity == 0) ? '' : product.stockQuantity.toString();
      _inStock = product.isInStock;
      _setCooldown(product.baleCooldownRemaining);
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
        stockQuantity: _normalizeNumber(_stockController.text),
        stockStatus: _inStock ? 'instock' : 'outofstock',
      );

      setState(() {
        _product = updated;
        _hasChanged = true;
      });
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


  Future<void> _changeFeaturedImage() async {
    if (_product == null || _uploadingImage) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2200,
      );
      if (picked == null) return;

      setState(() => _uploadingImage = true);
      final api = context.read<AuthProvider>().api;
      final updated = await api.updateProductImage(
        id: widget.productId,
        imagePath: picked.path,
      );

      setState(() {
        _product = updated;
        _hasChanged = true;
      });
      _showMessage('تصویر شاخص محصول تغییر کرد.');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('تغییر تصویر شاخص انجام نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _sendToBale() async {
    if (_product == null || _baleCooldown > 0) return;
    FocusScope.of(context).unfocus();

    setState(() => _sendingToBale = true);
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.sendProductToBale(
        id: widget.productId,
        manualText: _baleTextController.text,
      );
      _setCooldown(result.cooldownRemaining);
      _hasChanged = true;
      if (_product != null) {
        setState(() {
          _product = _product!.copyWith(
            lastAction: 'bale_sent',
            lastActionAt: DateTime.now().toUtc().toIso8601String(),
            baleSentActionAt: DateTime.now().toUtc().toIso8601String(),
          );
        });
      }
      _showMessage(result.message);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ارسال محصول به بله انجام نشد.');
    } finally {
      if (mounted) setState(() => _sendingToBale = false);
    }
  }

  void _setCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (!mounted) {
      _baleCooldown = seconds;
      return;
    }
    setState(() => _baleCooldown = seconds < 0 ? 0 : seconds);
    if (_baleCooldown <= 0) return;

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_baleCooldown <= 1) {
        timer.cancel();
        setState(() => _baleCooldown = 0);
      } else {
        setState(() => _baleCooldown--);
      }
    });
  }

  void _openBaleSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BaleSettingsScreen()),
    );
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

  String _formatCooldown(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes دقیقه';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m == 0 ? '$h ساعت' : '$h ساعت و $m دقیقه';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_hasChanged);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_product?.name ?? widget.productName)),
        body: _buildBody(),
      ),
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
            _ProductHeader(
              product: product,
              uploadingImage: _uploadingImage,
              onChangeImage: _changeFeaturedImage,
            ),
            const SizedBox(height: 14),
            _editCard(),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تغییرات'),
            ),
            const SizedBox(height: 14),
            _baleCard(),
          ],
        ),
      ),
    );
  }

  Widget _editCard() {
    return Card(
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
                hintText: 'خالی یا ۰ = بدون محدودیت تعداد',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (value) {
                final text = _normalizeNumber(value ?? '');
                if (text.isEmpty) return null;
                final number = int.tryParse(text);
                if (number == null || number < 0) return 'تعداد انبار معتبر نیست.';
                return null;
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'اگر موجودی را خالی بگذاری یا ۰ بزنی، یعنی محدودیت تعداد نداریم.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.3, height: 1.5),
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
                  const Expanded(child: Text('وضعیت موجودی', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(_inStock ? 'موجود' : 'ناموجود'),
                  const SizedBox(width: 8),
                  Switch(value: _inStock, onChanged: (value) => setState(() => _inStock = value)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _baleCard() {
    final disabled = _sendingToBale || _baleCooldown > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ارسال در کانال بله', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('پست بدون نمایش موجودی منتشر می‌شود', style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تنظیمات بله',
                  onPressed: _openBaleSettings,
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _baleTextController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'متن دستی زیر عکس، قبل از مشخصات و قیمت',
                hintText: 'مثلاً: فروش ویژه امروز، ارسال فوری...',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 14),
            if (_baleCooldown > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  'این محصول تازه ارسال شده؛ ارسال دوباره تا ${_formatCooldown(_baleCooldown)} دیگر غیرفعال است.',
                  style: const TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w800),
                ),
              ),
            OutlinedButton.icon(
              onPressed: disabled ? null : _sendToBale,
              icon: _sendingToBale
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(_sendingToBale ? 'در حال ارسال...' : 'ارسال در کانال'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({
    required this.product,
    required this.uploadingImage,
    required this.onChangeImage,
  });

  final Product product;
  final bool uploadingImage;
  final VoidCallback onChangeImage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 94,
                    height: 94,
                    color: const Color(0xFFEFF6FF),
                    child: product.imageUrl.isEmpty
                        ? const Icon(Icons.image_outlined, color: Color(0xFF2563EB), size: 34)
                        : Image.network(
                            product.imageUrl,
                            key: ValueKey(product.imageUrl),
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
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
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
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: uploadingImage ? null : onChangeImage,
              icon: uploadingImage
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(uploadingImage ? 'در حال آپلود تصویر...' : 'تغییر تصویر شاخص'),
            ),
            const SizedBox(height: 6),
            const Text(
              'تصویر انتخاب‌شده به عنوان تصویر اصلی محصول در ووکامرس ذخیره می‌شود.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

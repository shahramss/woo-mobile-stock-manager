import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/local_product_action_store.dart';
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
  bool _uploadingGallery = false;
  bool _deletingGallery = false;
  bool _inStock = true;
  bool _hasChanged = false;
  int _baleCooldown = 0;
  String? _error;
  String? _pendingFeaturedImagePath;

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

  Future<void> _loadProduct({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final api = context.read<AuthProvider>().api;
      final product = await api.getProduct(widget.productId);
      final localProduct = await LocalProductActionStore.applyToProduct(product);
      if (!mounted) return;
      setState(() {
        _product = localProduct;
        _priceController.text = localProduct.regularPrice;
        _stockController.text = (localProduct.stockQuantity == null || localProduct.stockQuantity == 0) ? '' : localProduct.stockQuantity.toString();
        _inStock = localProduct.isInStock;
        _error = null;
      });
      _setCooldown(localProduct.baleCooldownRemaining);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'جزئیات محصول دریافت نشد.');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _product == null) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      final api = context.read<AuthProvider>().api;

      await api.updateProduct(
        id: widget.productId,
        regularPrice: _normalizeNumber(_priceController.text),
        stockQuantity: _normalizeNumber(_stockController.text),
        stockStatus: _inStock ? 'instock' : 'outofstock',
      );

      // اگر کاربر تصویر شاخص جدید انتخاب کرده باشد، همین ذخیره تغییرات آن را هم مستقل ثبت می‌کند.
      if (_pendingFeaturedImagePath != null && _pendingFeaturedImagePath!.isNotEmpty) {
        await api.updateProductImage(
          id: widget.productId,
          imagePath: _pendingFeaturedImagePath!,
        );
      }

      // بعد از ذخیره، محصول از سرور دوباره گرفته می‌شود تا هیچ کش یا اطلاعات قدیمی در اپ نماند.
      final fresh = await api.getProduct(widget.productId);
      await LocalProductActionStore.markUpdated(widget.productId);
      final localUpdated = await LocalProductActionStore.applyToProduct(fresh);

      if (!mounted) return;
      setState(() {
        _product = localUpdated;
        _pendingFeaturedImagePath = null;
        _priceController.text = localUpdated.regularPrice;
        _stockController.text = (localUpdated.stockQuantity == null || localUpdated.stockQuantity == 0) ? '' : localUpdated.stockQuantity.toString();
        _inStock = localUpdated.isInStock;
        _hasChanged = true;
      });
      _showMessage('تغییرات از سایت ذخیره و دوباره دریافت شد. برای برگشت، ضربدر بالا را بزنید.');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ذخیره تغییرات انجام نشد. اتصال سایت و افزونه را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFeaturedImage() async {
    if (_product == null || _saving) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2200,
      );
      if (picked == null) return;

      setState(() => _pendingFeaturedImagePath = picked.path);
      _showMessage('تصویر شاخص انتخاب شد. برای ثبت در سایت روی «ذخیره تغییرات» بزنید.');
    } catch (_) {
      _showMessage('انتخاب تصویر انجام نشد.');
    }
  }

  Future<void> _addGalleryImage() async {
    if (_product == null || _uploadingGallery) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2200,
      );
      if (picked == null) return;

      setState(() => _uploadingGallery = true);
      final api = context.read<AuthProvider>().api;
      await api.addProductGalleryImage(id: widget.productId, imagePath: picked.path);

      final fresh = await api.getProduct(widget.productId);
      await LocalProductActionStore.markUpdated(widget.productId);
      final localUpdated = await LocalProductActionStore.applyToProduct(fresh);
      if (!mounted) return;
      setState(() {
        _product = localUpdated;
        _hasChanged = true;
      });
      _showMessage('تصویر به گالری محصول اضافه شد.');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('اضافه کردن تصویر گالری انجام نشد.');
    } finally {
      if (mounted) setState(() => _uploadingGallery = false);
    }
  }

  Future<void> _deleteGalleryImage(ProductGalleryImage image) async {
    if (_product == null || _deletingGallery) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف تصویر گالری'),
        content: const Text('این تصویر فقط از گالری همین محصول حذف می‌شود. ادامه می‌دهی؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingGallery = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.deleteProductGalleryImage(id: widget.productId, imageId: image.id);

      final fresh = await api.getProduct(widget.productId);
      await LocalProductActionStore.markUpdated(widget.productId);
      final localUpdated = await LocalProductActionStore.applyToProduct(fresh);
      if (!mounted) return;
      setState(() {
        _product = localUpdated;
        _hasChanged = true;
      });
      _showMessage('تصویر از گالری محصول حذف شد.');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('حذف تصویر گالری انجام نشد.');
    } finally {
      if (mounted) setState(() => _deletingGallery = false);
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
      await LocalProductActionStore.markBaleSent(widget.productId);
      _hasChanged = true;

      // بعد از ارسال به بله هم محصول از سرور گرفته می‌شود، ولی رنگ کارت بر اساس اکشن محلی اپ باقی می‌ماند.
      final fresh = await api.getProduct(widget.productId);
      final localProduct = await LocalProductActionStore.applyToProduct(fresh);
      if (mounted) setState(() => _product = localProduct);

      _showMessage('${result.message} برای برگشت، ضربدر بالا را بزنید.');
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
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'بستن',
            onPressed: () => Navigator.of(context).pop(_hasChanged),
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            IconButton(
              tooltip: 'دریافت دوباره از سایت',
              onPressed: _saving ? null : () => _loadProduct(silent: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          title: Text(_product?.name ?? widget.productName),
        ),
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
          ElevatedButton(onPressed: () => _loadProduct(), child: const Text('تلاش دوباره')),
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
              pendingFeaturedImagePath: _pendingFeaturedImagePath,
              onChangeImage: _pickFeaturedImage,
            ),
            const SizedBox(height: 14),
            _GalleryCard(
              images: product.galleryImages,
              uploading: _uploadingGallery,
              deleting: _deletingGallery,
              onAdd: _addGalleryImage,
              onDelete: _deleteGalleryImage,
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
                color: const Color(0xFFFFF7FB),
                border: Border.all(color: const Color(0xFFFBCFE8)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFFEC4899)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('وضعیت موجودی', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(_inStock ? 'موجود' : 'ناموجود'),
                  const SizedBox(width: 8),
                  Switch(value: _inStock, onChanged: (value) => setState(() => _inStock = value)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'برای ناموجود کردن محصول اول تعداد در انبار ۰ بزنید و بعد روی دکمه ناموجود کنید، سپس روی ذخیره تغییرات بزنید.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.3, height: 1.5),
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
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Color(0xFFEC4899)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ارسال در کانال بله', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('این محصول را در کانال بله وارد کنید', style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
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
    required this.pendingFeaturedImagePath,
    required this.onChangeImage,
  });

  final Product product;
  final String? pendingFeaturedImagePath;
  final VoidCallback onChangeImage;

  @override
  Widget build(BuildContext context) {
    final hasPendingImage = pendingFeaturedImagePath != null && pendingFeaturedImagePath!.isNotEmpty;
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
                    color: const Color(0xFFFDF2F8),
                    child: hasPendingImage
                        ? Image.file(File(pendingFeaturedImagePath!), fit: BoxFit.cover)
                        : product.imageUrl.isEmpty
                            ? const Icon(Icons.image_outlined, color: Color(0xFFEC4899), size: 34)
                            : Image.network(
                                product.imageUrl,
                                key: ValueKey(product.imageUrl),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFFEC4899), size: 34),
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
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF311124)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.isInStock ? 'موجود' : 'ناموجود',
                        style: TextStyle(
                          color: product.isInStock ? const Color(0xFF166534) : const Color(0xFF991B1B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (hasPendingImage) ...[
                        const SizedBox(height: 6),
                        const Text('تصویر جدید آماده ذخیره است', style: TextStyle(color: Color(0xFFEC4899), fontSize: 12, fontWeight: FontWeight.w900)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onChangeImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('انتخاب تصویر شاخص'),
            ),
            const SizedBox(height: 6),
            const Text(
              'بعد از انتخاب تصویر، برای ثبت در سایت روی «ذخیره تغییرات» بزنید.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.images,
    required this.uploading,
    required this.deleting,
    required this.onAdd,
    required this.onDelete,
  });

  final List<ProductGalleryImage> images;
  final bool uploading;
  final bool deleting;
  final VoidCallback onAdd;
  final ValueChanged<ProductGalleryImage> onDelete;

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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('گالری تصاویر محصول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text('تصاویر را حذف یا اضافه کنید، سپس روی ذخیره تغییرات بزنید', style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'افزودن تصویر گالری',
                  onPressed: uploading || deleting ? null : onAdd,
                  icon: uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AddGalleryTile(onTap: uploading || deleting ? null : onAdd, uploading: uploading);
                  }
                  final image = images[index - 1];
                  return _GalleryImageTile(
                    image: image,
                    disabled: deleting || uploading,
                    onDelete: () => onDelete(image),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGalleryTile extends StatelessWidget {
  const _AddGalleryTile({required this.onTap, required this.uploading});

  final VoidCallback? onTap;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFFDF2F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFBCFE8)),
        ),
        child: Center(
          child: uploading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_rounded, color: Color(0xFFEC4899), size: 34),
        ),
      ),
    );
  }
}

class _GalleryImageTile extends StatelessWidget {
  const _GalleryImageTile({required this.image, required this.disabled, required this.onDelete});

  final ProductGalleryImage image;
  final bool disabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 100,
              height: 100,
              color: const Color(0xFFFDF2F8),
              child: image.url.isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFFEC4899))
                  : Image.network(
                      image.url,
                      key: ValueKey(image.url),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFFEC4899)),
                    ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: const Color(0xFFE11D48),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: disabled ? null : onDelete,
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/product_category.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/local_product_action_store.dart';
import '../widgets/empty_state.dart';
import 'product_detail_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.category});

  final ProductCategory? category;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Product> _products = [];

  Timer? _searchDebounce;
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _autoStarting = false;
  String _search = '';
  String _sort = 'newest';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts(refresh: true);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 260) {
      if (!_isLoading && _hasMore) {
        _loadProducts();
      }
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 550), () {
      final value = _searchController.text.trim();
      if (value == _search) return;
      setState(() => _search = value);
      _loadProducts(refresh: true);
    });
  }

  Future<void> _loadProducts({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _page = 1;
        _hasMore = true;
        _products.clear();
      }
    });

    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.getProducts(
        categoryId: widget.category?.id,
        search: _search,
        sort: _sort,
        page: _page,
        perPage: 20,
      );
      final localItems = await LocalProductActionStore.applyToProducts(result.items);
      setState(() {
        _products.addAll(localItems);
        _hasMore = result.hasMore;
        _page += 1;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'محصولات دریافت نشدند. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openProduct(Product product) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: product.id, productName: product.name),
      ),
    );

    if (updated == true) {
      await _loadProducts(refresh: true);
    }
  }

  Future<void> _openAutoPostDialog() async {
    final category = widget.category;
    if (category == null) {
      _showMessage('برای ارسال خودکار، اول یک دسته‌بندی را انتخاب کنید.');
      return;
    }

    final textController = TextEditingController();
    var selectedInterval = 60;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ارسال خودکار دسته به بله'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('محصولات دسته «${category.name}» به ترتیب در کانال بله منتشر می‌شوند.'),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: selectedInterval,
                      decoration: const InputDecoration(
                        labelText: 'فاصله بین هر پست',
                        prefixIcon: Icon(Icons.timer_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('هر ۳ دقیقه')),
                        DropdownMenuItem(value: 60, child: Text('هر ۱ ساعت')),
                        DropdownMenuItem(value: 420, child: Text('هر ۷ ساعت')),
                        DropdownMenuItem(value: 1440, child: Text('هر ۲۴ ساعت')),
                      ],
                      onChanged: (value) => setDialogState(() => selectedInterval = value ?? 60),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: textController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'متن ثابت قبل از مشخصات و قیمت',
                        hintText: 'مثلاً: معرفی محصولات این دسته...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'نکته: زمان‌بندی روی وردپرس انجام می‌شود و اگر سایت بازدید نداشته باشد، ممکن است ارسال کمی دیرتر انجام شود.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.6),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('لغو'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('شروع ارسال'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      textController.dispose();
      return;
    }

    setState(() => _autoStarting = true);
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.startBaleAutoPost(
        categoryId: category.id,
        intervalMinutes: selectedInterval,
        manualText: textController.text,
      );
      _showMessage('${result.message} تعداد محصولات: ${result.total}');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('فعال‌سازی ارسال خودکار انجام نشد.');
    } finally {
      textController.dispose();
      if (mounted) setState(() => _autoStarting = false);
    }
  }


  Future<void> _stopAutoPost() async {
    final category = widget.category;
    if (category == null) return;

    setState(() => _autoStarting = true);
    try {
      final api = context.read<AuthProvider>().api;
      final message = await api.stopBaleAutoPost(categoryId: category.id);
      _showMessage(message);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('توقف ارسال خودکار انجام نشد.');
    } finally {
      if (mounted) setState(() => _autoStarting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _sortLabel(String value) {
    switch (value) {
      case 'price_desc':
        return 'بیشترین قیمت';
      case 'price_asc':
        return 'کمترین قیمت';
      case 'oldest':
        return 'قدیمی‌ترین';
      case 'newest':
      default:
        return 'جدیدترین محصول';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.category?.name ?? 'همه محصولات';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadProducts(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header(title)),
              if (_error != null && _products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EmptyState(message: _error!, icon: Icons.error_outline),
                        const SizedBox(height: 18),
                        ElevatedButton(onPressed: () => _loadProducts(refresh: true), child: const Text('تلاش دوباره')),
                      ],
                    ),
                  ),
                )
              else if (_isLoading && _products.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_products.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(message: 'محصولی پیدا نشد'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index.isOdd) return const SizedBox(height: 12);
                        final itemIndex = index ~/ 2;
                        if (itemIndex >= _products.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final product = _products[itemIndex];
                        return _ProductCard(product: product, onTap: () => _openProduct(product));
                      },
                      childCount: ((_products.length + (_hasMore ? 1 : 0)) * 2) - 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFDB2777), Color(0xFFF9A8D4)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDB2777).withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'لیست محصولات',
                      style: TextStyle(color: Color(0xFFFCE7F3), fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'جستجوی محصول در همین دسته...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _search = '';
                        _loadProducts(refresh: true);
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.98),
              borderRadius: BorderRadius.circular(18),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sort,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('جدیدترین محصولات به قدیمی‌ترین')),
                  DropdownMenuItem(value: 'oldest', child: Text('قدیمی‌ترین محصولات به جدیدترین')),
                  DropdownMenuItem(value: 'price_desc', child: Text('بیشترین قیمت به کمتر')),
                  DropdownMenuItem(value: 'price_asc', child: Text('کمترین قیمت به بیشتر')),
                ],
                onChanged: (value) {
                  if (value == null || value == _sort) return;
                  setState(() => _sort = value);
                  _loadProducts(refresh: true);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.sort_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'مرتب‌سازی فعلی: ${_sortLabel(_sort)}',
                  style: const TextStyle(color: Color(0xFFFCE7F3), fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (widget.category != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.7)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _autoStarting ? null : _openAutoPostDialog,
                    icon: _autoStarting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.campaign_rounded),
                    label: Text(_autoStarting ? 'در حال انجام...' : 'ارسال خودکار'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.55)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _autoStarting ? null : _stopAutoPost,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('توقف'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _actionStyle(product);

    return Card(
      color: Colors.transparent,
      elevation: product.hasRecentAction ? 1.8 : 0.8,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: style.border, width: product.hasRecentAction ? 1.4 : 0.7),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: style.gradient == null ? style.background : null,
          gradient: style.gradient,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
              _ProductImage(imageUrl: product.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (style.label.isNotEmpty) ...[
                          _ActionBadge(label: style.label, color: style.badgeColor),
                          const SizedBox(width: 7),
                        ],
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StockBadge(isInStock: product.isInStock),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            product.regularPrice.isEmpty ? 'بدون قیمت' : '${product.regularPrice} تومان',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ProductActionStyle _actionStyle(Product product) {
    if (product.hasBothRecentActions) {
      return const _ProductActionStyle(
        background: Colors.white,
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xFFDBEAFE), Color(0xFFD1FAE5)],
        ),
        border: Color(0xFF10B981),
        badgeColor: Color(0xFF0F766E),
        label: 'بروزرسانی + ارسال بله',
      );
    }
    if (product.wasSentToBaleLast) {
      return const _ProductActionStyle(
        background: Color(0xFFF0FDF4),
        border: Color(0xFF86EFAC),
        badgeColor: Color(0xFF16A34A),
        label: 'ارسال بله',
      );
    }
    if (product.wasUpdatedLast) {
      return const _ProductActionStyle(
        background: Color(0xFFEFF6FF),
        border: Color(0xFF93C5FD),
        badgeColor: Color(0xFF2563EB),
        label: 'بروزرسانی',
      );
    }
    return const _ProductActionStyle(
      background: Colors.white,
      border: Color(0xFFE2E8F0),
      badgeColor: Color(0xFF64748B),
      label: '',
    );
  }
}

class _ProductActionStyle {
  const _ProductActionStyle({
    required this.background,
    this.gradient,
    required this.border,
    required this.badgeColor,
    required this.label,
  });

  final Color background;
  final Gradient? gradient;
  final Color border;
  final Color badgeColor;
  final String label;
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 72,
        height: 72,
        color: const Color(0xFFFDF2F8),
        child: imageUrl.isEmpty
            ? const Icon(Icons.image_not_supported_outlined, color: Color(0xFFEC4899), size: 30)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFFEC4899), size: 30),
              ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.isInStock});
  final bool isInStock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isInStock ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isInStock ? 'موجود' : 'ناموجود',
        style: TextStyle(
          color: isInStock ? const Color(0xFF166534) : const Color(0xFF991B1B),
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

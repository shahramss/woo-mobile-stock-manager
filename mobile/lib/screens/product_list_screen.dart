import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/product_category.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
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
  String _search = '';
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
        page: _page,
        perPage: 20,
      );
      setState(() {
        _products.addAll(result.items);
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
                        if (index.isOdd) {
                          return const SizedBox(height: 12);
                        }
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
          colors: [Color(0xFF1E40AF), Color(0xFF60A5FA)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withOpacity(0.18),
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
                      style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 12.5, fontWeight: FontWeight.w700),
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
    return Card(
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
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
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
        color: const Color(0xFFEFF6FF),
        child: imageUrl.isEmpty
            ? const Icon(Icons.image_not_supported_outlined, color: Color(0xFF2563EB), size: 30)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFF2563EB), size: 30),
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

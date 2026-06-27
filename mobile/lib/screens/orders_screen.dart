import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<OrderSummary> _orders = [];
  Timer? _timeRefreshTimer;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders(refresh: true);
    _scrollController.addListener(_onScroll);
    // زمان نسبی سفارش‌ها مثل «۱۶ ساعت قبل» بدون دریافت دوباره از سرور بروزرسانی می‌شود.
    _timeRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _orders.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeRefreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 260) {
      if (!_loading && _hasMore) _loadOrders();
    }
  }

  Future<void> _loadOrders({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _page = 1;
        _hasMore = true;
        _orders.clear();
      }
    });

    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.getOrders(page: _page, perPage: 20);
      setState(() {
        _orders.addAll(result.items);
        _hasMore = result.hasMore;
        _page++;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'سفارش‌ها دریافت نشدند. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openOrder(OrderSummary order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id, orderNumber: order.number)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: ElevatedButton.icon(
          onPressed: _loading ? null : () => _loadOrders(refresh: true),
          icon: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.refresh_rounded),
          label: Text(_loading ? 'در حال بروزرسانی...' : 'بروزرسانی سفارش‌ها'),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadOrders(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              if (_error != null && _orders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EmptyState(message: _error!, icon: Icons.error_outline),
                        const SizedBox(height: 18),
                        ElevatedButton(onPressed: () => _loadOrders(refresh: true), child: const Text('تلاش دوباره')),
                      ],
                    ),
                  ),
                )
              else if (_loading && _orders.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (_orders.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: EmptyState(message: 'سفارشی پیدا نشد'))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index.isOdd) return const SizedBox(height: 12);
                        final itemIndex = index ~/ 2;
                        if (itemIndex >= _orders.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final order = _orders[itemIndex];
                        return _OrderCard(order: order, onTap: () => _openOrder(order));
                      },
                      childCount: ((_orders.length + (_hasMore ? 1 : 0)) * 2) - 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFDB2777), Color(0xFFF9A8D4)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDB2777).withOpacity(0.20),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سفارشات', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('زمان سفارش‌ها خودکار بروزرسانی می‌شود؛ برای سفارش‌های تازه دکمه پایین صفحه را بزنید', style: TextStyle(color: Color(0xFFFCE7F3), fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _loadOrders(refresh: true),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});
  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF2F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFEC4899)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('سفارش #${order.number}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                        _StatusBadge(label: order.statusLabel),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(order.customerName.isEmpty ? 'بدون نام مشتری' : order.customerName, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: Text(_timeAgo(order.dateCreated), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5))),
                        Text('${order.total} تومان', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900)),
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

  String _timeAgo(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inMinutes < 1) return 'چند لحظه قبل';
    if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقه قبل';
    if (diff.inHours < 24) return '${diff.inHours} ساعت قبل';
    return '${diff.inDays} روز قبل';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(999)),
      child: Text(label.isEmpty ? 'جدید' : label, style: const TextStyle(color: Color(0xFF166534), fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

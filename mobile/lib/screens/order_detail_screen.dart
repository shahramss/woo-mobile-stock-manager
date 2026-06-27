import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/order.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, required this.orderNumber});

  final int orderId;
  final String orderNumber;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final GlobalKey _invoiceKey = GlobalKey();
  OrderDetail? _order;
  bool _loading = true;
  bool _creatingInvoice = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final order = await api.getOrder(widget.orderId);
      setState(() => _order = order);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'جزئیات سفارش دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareInvoicePng() async {
    if (_order == null || _creatingInvoice) return;
    setState(() => _creatingInvoice = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final boundary = _invoiceKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('invoice boundary not found');
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) throw Exception('empty png');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice-${_order!.number}.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'invoice-${_order!.number}.png')],
        text: 'فاکتور سفارش #${_order!.number}',
      );
    } catch (_) {
      _showMessage('ساخت فاکتور PNG انجام نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _creatingInvoice = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'بستن',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text('سفارش #${widget.orderNumber}'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 80),
          EmptyState(message: _error!, icon: Icons.error_outline),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _loadOrder, child: const Text('تلاش دوباره')),
        ],
      );
    }

    final order = _order!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RepaintBoundary(
          key: _invoiceKey,
          child: _InvoiceCard(order: order),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _creatingInvoice ? null : _shareInvoicePng,
          icon: _creatingInvoice
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.image_outlined),
          label: Text(_creatingInvoice ? 'در حال ساخت فاکتور...' : 'ساخت و ارسال فاکتور PNG'),
        ),
        const SizedBox(height: 10),
        const Text(
          'بعد از ساخت PNG، از صفحه اشتراک گوشی می‌توانید فاکتور را برای ارسال، ذخیره یا چاپ انتخاب کنید.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.6),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.order});
  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFFBCFE8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFDB2777), Color(0xFFF9A8D4)]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('فاکتور سفارش', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF311124))),
                        const SizedBox(height: 4),
                        Text('#${order.number} - ${_formatDate(order.dateCreated)}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              _InfoRow(label: 'مشتری', value: order.customerName.isEmpty ? '-' : order.customerName),
              _InfoRow(label: 'شماره تماس', value: order.phone.isEmpty ? '-' : order.phone),
              _InfoRow(label: 'کدپستی', value: order.postcode.isEmpty ? '-' : order.postcode),
              _InfoRow(label: 'آدرس', value: order.address.isEmpty ? '-' : order.address),
              _InfoRow(label: 'درگاه پرداخت', value: order.paymentMethodTitle.isEmpty ? '-' : order.paymentMethodTitle),
              _InfoRow(label: 'وضعیت', value: order.statusLabel),
              const SizedBox(height: 14),
              const Text('محصولات سفارش', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 10),
              ...order.items.map((item) => _OrderItemRow(item: item)),
              const Divider(height: 28),
              _TotalRow(label: 'هزینه ارسال', value: '${order.shippingTotal} تومان'),
              const SizedBox(height: 8),
              _TotalRow(label: 'مبلغ کل پرداخت شده', value: '${order.total} تومان', bold: true),
              const SizedBox(height: 12),
              const Text(
                'مدیریت سریع | طراحی و ساخت: شهرام سعیدنیا',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final local = date.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} - ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800))),
          Expanded(child: Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, height: 1.5))),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFBCFE8)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 54,
              height: 54,
              color: Colors.white,
              child: item.imageUrl.isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFFEC4899))
                  : Image.network(item.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFFEC4899))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 5),
                Text('تعداد: ${item.quantity} | قیمت واحد: ${item.price} تومان', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${item.total} تومان', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: const Color(0xFF0F172A), fontSize: bold ? 16 : 14, fontWeight: FontWeight.w900))),
        Text(value, style: TextStyle(color: const Color(0xFFDB2777), fontSize: bold ? 17 : 14, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';

class LocalProductActionStore {
  static const _updatedPrefix = 'wmsm_local_updated_';
  static const _balePrefix = 'wmsm_local_bale_';

  static Future<void> markUpdated(int productId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_updatedPrefix$productId', DateTime.now().toUtc().toIso8601String());
  }

  static Future<void> markBaleSent(int productId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_balePrefix$productId', DateTime.now().toUtc().toIso8601String());
  }

  static Future<Product> applyToProduct(Product product) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAt = _recentOrEmpty(prefs.getString('$_updatedPrefix${product.id}') ?? '');
    final baleAt = _recentOrEmpty(prefs.getString('$_balePrefix${product.id}') ?? '');

    var finalUpdated = product.updatedActionAt;
    var finalBale = product.baleSentActionAt;
    if (updatedAt.isNotEmpty) finalUpdated = updatedAt;
    if (baleAt.isNotEmpty) finalBale = baleAt;

    final hasUpdated = _isRecent(finalUpdated);
    final hasBale = _isRecent(finalBale);
    final state = hasUpdated && hasBale
        ? 'both'
        : hasUpdated
            ? 'updated'
            : hasBale
                ? 'bale_sent'
                : product.actionState;

    return product.copyWith(
      updatedActionAt: finalUpdated,
      baleSentActionAt: finalBale,
      lastAction: hasBale ? 'bale_sent' : (hasUpdated ? 'updated' : product.lastAction),
      lastActionAt: hasBale ? finalBale : (hasUpdated ? finalUpdated : product.lastActionAt),
      actionState: state,
    );
  }

  static Future<List<Product>> applyToProducts(List<Product> products) async {
    final result = <Product>[];
    for (final product in products) {
      result.add(await applyToProduct(product));
    }
    return result;
  }

  static String _recentOrEmpty(String value) => _isRecent(value) ? value : '';

  static bool _isRecent(String value) {
    if (value.isEmpty) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    return !diff.isNegative && diff.inHours < 24;
  }
}

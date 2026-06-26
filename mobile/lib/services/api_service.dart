import 'package:dio/dio.dart';

import '../models/login_result.dart';
import '../models/product.dart';
import '../models/product_category.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ProductPage {
  ProductPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<Product> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class ApiService {
  ApiService({required String siteUrl, String? token})
      : _siteUrl = _cleanSiteUrl(siteUrl) {
    _dio = Dio(
      BaseOptions(
        baseUrl: '$_siteUrl/wp-json/wmsm/v1',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          if (token != null && token.isNotEmpty) 'X-WMSM-Token': token,
        },
      ),
    );
  }

  final String _siteUrl;
  late final Dio _dio;

  static String _cleanSiteUrl(String value) {
    var url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/login',
        data: {
          'username': username.trim(),
          'password': password,
        },
      );
      final data = response.data ?? {};
      final token = (data['token'] ?? '').toString();
      if (token.isEmpty) {
        throw ApiException('توکن ورود از سایت دریافت نشد.');
      }
      return LoginResult.fromJson(data, _siteUrl);
    } on DioException catch (e) {
      throw ApiException(_readDioError(e));
    }
  }

  Future<List<ProductCategory>> getCategories() async {
    try {
      final response = await _dio.get<List<dynamic>>('/categories');
      final itemsJson = response.data ?? [];
      return itemsJson
          .whereType<Map<String, dynamic>>()
          .map(ProductCategory.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException(_readDioError(e));
    }
  }

  Future<ProductPage> getProducts({
    int? categoryId,
    String search = '',
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {
          if (categoryId != null && categoryId > 0) 'category_id': categoryId,
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'page': page,
          'per_page': perPage,
        },
      );
      final data = response.data ?? {};
      final itemsJson = (data['items'] as List<dynamic>? ?? []);
      return ProductPage(
        items: itemsJson
            .whereType<Map<String, dynamic>>()
            .map(Product.fromJson)
            .toList(),
        page: int.tryParse((data['page'] ?? page).toString()) ?? page,
        totalPages: int.tryParse((data['total_pages'] ?? page).toString()) ?? page,
      );
    } on DioException catch (e) {
      throw ApiException(_readDioError(e));
    }
  }

  Future<Product> getProduct(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/products/$id');
      return Product.fromJson(response.data ?? {});
    } on DioException catch (e) {
      throw ApiException(_readDioError(e));
    }
  }

  Future<Product> updateProduct({
    required int id,
    required String regularPrice,
    required int stockQuantity,
    required String stockStatus,
  }) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/products/$id',
        data: {
          'regular_price': regularPrice.trim(),
          'stock_quantity': stockQuantity,
          'stock_status': stockStatus,
        },
      );
      return Product.fromJson(response.data ?? {});
    } on DioException catch (e) {
      throw ApiException(_readDioError(e));
    }
  }

  String _readDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'ارتباط با سایت طولانی شد. دوباره تلاش کنید.';
      case DioExceptionType.badCertificate:
        return 'گواهی SSL سایت معتبر نیست.';
      case DioExceptionType.connectionError:
        return 'اتصال به سایت برقرار نشد. آدرس سایت را بررسی کنید.';
      default:
        if (e.response?.statusCode == 404) {
          return 'مسیر افزونه در سایت پیدا نشد. فعال بودن افزونه را بررسی کنید.';
        }
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          return 'دسترسی شما مجاز نیست یا نشست منقضی شده است.';
        }
        return 'خطای نامشخص رخ داد. دوباره تلاش کنید.';
    }
  }
}

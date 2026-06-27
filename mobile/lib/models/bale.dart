import 'product.dart';

class BaleSettings {
  BaleSettings({
    required this.hasBotToken,
    required this.chatId,
    required this.jobs,
  });

  final bool hasBotToken;
  final String chatId;
  final List<BaleAutoJob> jobs;

  factory BaleSettings.fromJson(Map<String, dynamic> json) {
    final rawJobs = json['jobs'] as List<dynamic>? ?? [];
    return BaleSettings(
      hasBotToken: json['has_bot_token'] == true,
      chatId: (json['chat_id'] ?? '').toString(),
      jobs: rawJobs
          .whereType<Map<String, dynamic>>()
          .map(BaleAutoJob.fromJson)
          .toList(),
    );
  }
}

class BaleSendResult {
  BaleSendResult({required this.message, required this.cooldownRemaining, this.product});

  final String message;
  final int cooldownRemaining;
  final Product? product;

  factory BaleSendResult.fromJson(Map<String, dynamic> json) {
    final productJson = json['product'];
    return BaleSendResult(
      message: (json['message'] ?? 'محصول در کانال بله منتشر شد.').toString(),
      cooldownRemaining: int.tryParse((json['cooldown_remaining'] ?? '0').toString()) ?? 0,
      product: productJson is Map<String, dynamic> ? Product.fromJson(productJson) : null,
    );
  }
}

class BaleAutoStartResult {
  BaleAutoStartResult({
    required this.message,
    required this.total,
    required this.intervalMinutes,
    required this.nextRun,
  });

  final String message;
  final int total;
  final int intervalMinutes;
  final String nextRun;

  factory BaleAutoStartResult.fromJson(Map<String, dynamic> json) {
    return BaleAutoStartResult(
      message: (json['message'] ?? 'ارسال خودکار فعال شد.').toString(),
      total: int.tryParse((json['total'] ?? '0').toString()) ?? 0,
      intervalMinutes: int.tryParse((json['interval_minutes'] ?? '0').toString()) ?? 0,
      nextRun: (json['next_run'] ?? '').toString(),
    );
  }
}

class BaleAutoJob {
  BaleAutoJob({
    required this.categoryId,
    required this.categoryName,
    required this.intervalMinutes,
    required this.sentCount,
    required this.total,
    required this.nextRun,
    required this.status,
  });

  final int categoryId;
  final String categoryName;
  final int intervalMinutes;
  final int sentCount;
  final int total;
  final String nextRun;
  final String status;

  factory BaleAutoJob.fromJson(Map<String, dynamic> json) {
    return BaleAutoJob(
      categoryId: int.tryParse((json['category_id'] ?? '0').toString()) ?? 0,
      categoryName: (json['category_name'] ?? '').toString(),
      intervalMinutes: int.tryParse((json['interval_minutes'] ?? '0').toString()) ?? 0,
      sentCount: int.tryParse((json['sent_count'] ?? '0').toString()) ?? 0,
      total: int.tryParse((json['total'] ?? '0').toString()) ?? 0,
      nextRun: (json['next_run'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bale.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class BaleSettingsScreen extends StatefulWidget {
  const BaleSettingsScreen({super.key});

  @override
  State<BaleSettingsScreen> createState() => _BaleSettingsScreenState();
}

class _BaleSettingsScreenState extends State<BaleSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  BaleSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final settings = await api.getBaleSettings();
      _settings = settings;
      _chatIdController.text = settings.chatId;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'تنظیمات بله دریافت نشد.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final api = context.read<AuthProvider>().api;
      final settings = await api.saveBaleSettings(
        botToken: _tokenController.text,
        chatId: _chatIdController.text,
      );
      setState(() {
        _settings = settings;
        _tokenController.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات بله ذخیره شد')),
      );
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ذخیره تنظیمات بله انجام نشد.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات کانال بله')),
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
          ElevatedButton(onPressed: _loadSettings, child: const Text('تلاش دوباره')),
        ],
      );
    }

    final hasToken = _settings?.hasBotToken ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF2F8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: Color(0xFFEC4899)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('اتصال به کانال بله', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              hasToken ? 'توکن قبلاً ذخیره شده است' : 'توکن بازوی بله هنوز ذخیره نشده',
                              style: TextStyle(
                                color: hasToken ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _tokenController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: hasToken ? 'توکن بازو؛ برای تغییر وارد کن' : 'توکن بازوی بله',
                      hintText: '123456789:abcdef...',
                      prefixIcon: const Icon(Icons.key_rounded),
                    ),
                    validator: (value) {
                      if (!hasToken && (value == null || value.trim().isEmpty)) {
                        return 'توکن بازوی بله را وارد کنید.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _chatIdController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'نام کاربری یا شناسه کانال',
                      hintText: '@channelusername',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'شناسه یا نام کاربری کانال را وارد کنید.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تنظیمات بله'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'راهنما: بازوی بله را با BotFather بساز، توکن را اینجا وارد کن، سپس بازو را مدیر کانال کن تا اجازه ارسال پست داشته باشد. اگر توکن قبلاً ذخیره شده، لازم نیست دوباره آن را وارد کنی.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.7),
            ),
          ),
        ),
      ],
    );
  }
}

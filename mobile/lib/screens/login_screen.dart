import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _siteController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hidePassword = true;


  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _siteController.text = auth.savedSiteUrl ?? 'https://example.com';
    _usernameController.text = auth.savedUsername ?? '';
    _passwordController.text = auth.savedPassword ?? '';
  }

  @override
  void dispose() {
    _siteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    try {
      await context.read<AuthProvider>().login(
            siteUrl: _siteController.text,
            username: _usernameController.text,
            password: _passwordController.text,
          );
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ورود انجام نشد. دوباره تلاش کنید.');
    }
  }



  Future<void> _loginWithBiometric() async {
    FocusScope.of(context).unfocus();
    try {
      await context.read<AuthProvider>().loginWithBiometric();
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('ورود با اثر انگشت انجام نشد.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isBusy = auth.isBusy;
    final hasSavedLogin = auth.hasSavedLogin;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x332563EB),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'مدیریت بانومی',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'مدیریت سریع قیمت و موجودی محصولات ووکامرس',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 26),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _siteController,
                              keyboardType: TextInputType.url,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'آدرس سایت',
                                hintText: 'https://example.com',
                                prefixIcon: Icon(Icons.language),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (text.isEmpty) return 'آدرس سایت را وارد کنید.';
                                if (!text.startsWith('http://') && !text.startsWith('https://')) {
                                  return 'آدرس باید با http یا https شروع شود.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'نام کاربری وردپرس',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) => (value == null || value.trim().isEmpty) ? 'نام کاربری را وارد کنید.' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _hidePassword,
                              decoration: InputDecoration(
                                labelText: 'رمز عبور وردپرس',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (value) => (value == null || value.isEmpty) ? 'رمز عبور را وارد کنید.' : null,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: isBusy ? null : _submit,
                              child: isBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                    )
                                  : const Text('ورود'),
                            ),
                            if (hasSavedLogin) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: isBusy ? null : _loginWithBiometric,
                                icon: const Icon(Icons.fingerprint_rounded),
                                label: const Text('ورود با اثر انگشت'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  side: const BorderSide(color: Color(0xFF2563EB)),
                                  foregroundColor: const Color(0xFF2563EB),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'اطلاعات ورود در حافظه امن گوشی ذخیره می‌شود.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سازنده: شهرام سعیدنیا',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

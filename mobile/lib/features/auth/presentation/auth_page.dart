import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';

final class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

final class _AuthPageState extends State<AuthPage> {
  static final _usernamePattern = RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}._-]{2,29}$', unicode: true);
  static final _phonePattern = RegExp(r'^\+?[0-9]{7,18}$');

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  Timer? _usernameTimer;
  Timer? _phoneTimer;
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String _role = 'customer';
  String? _error;
  String? _usernameFeedback;
  String? _phoneFeedback;
  bool? _usernameAvailable;
  bool? _phoneAvailable;

  @override
  void dispose() {
    _usernameTimer?.cancel();
    _phoneTimer?.cancel();
    _name.dispose();
    _username.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _queueAvailability(String field, String rawValue) {
    final value = rawValue.trim();
    final valid = field == 'username'
        ? _usernamePattern.hasMatch(value)
        : _phonePattern.hasMatch(value);
    if (!valid) {
      if (field == 'username') {
        _usernameTimer?.cancel();
      } else {
        _phoneTimer?.cancel();
      }
      setState(() {
        if (field == 'username') {
          _usernameAvailable = null;
          _usernameFeedback = value.isEmpty ? null : 'صيغة اسم المستخدم غير صحيحة.';
        } else {
          _phoneAvailable = null;
          _phoneFeedback = value.isEmpty ? null : 'أدخل رقماً من 7 إلى 18 رقماً.';
        }
      });
      return;
    }
    final timer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        if (field == 'username') {
          _usernameFeedback = 'جارٍ التحقق من التوفر…';
        } else {
          _phoneFeedback = 'جارٍ التحقق من التوفر…';
        }
      });
      try {
        final data = await AppScope.of(context).checkAvailability(
          field: field,
          value: value,
        );
        if (!mounted ||
            (field == 'username' ? _username.text.trim() : _phone.text.trim()) != value) {
          return;
        }
        final available = data['available'] == true;
        setState(() {
          if (field == 'username') {
            _usernameAvailable = available;
            _usernameFeedback = data['message'] as String? ?? (available ? 'اسم المستخدم متاح.' : 'اسم المستخدم محجوز.');
          } else {
            _phoneAvailable = available;
            _phoneFeedback = data['message'] as String? ?? (available ? 'رقم الهاتف متاح.' : 'رقم الهاتف مسجل بالفعل.');
          }
        });
      } on ApiException catch (error) {
        if (!mounted) return;
        setState(() {
          if (field == 'username') {
            _usernameAvailable = false;
            _usernameFeedback = error.message;
          } else {
            _phoneAvailable = false;
            _phoneFeedback = error.message;
          }
        });
      }
    });
    if (field == 'username') {
      _usernameTimer?.cancel();
      _usernameTimer = timer;
    } else {
      _phoneTimer?.cancel();
      _phoneTimer = timer;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final controller = AppScope.of(context);
      if (_isRegistering) {
        await controller.register(
          fullName: _name.text,
          username: _username.text,
          phone: _phone.text,
          password: _password.text,
          role: _role,
        );
      } else {
        await controller.login(phone: _phone.text, password: _password.text);
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إتمام العملية الآن. حاول لاحقاً.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _availabilityNote(String? text, bool? available) {
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = available == null
        ? theme.colorScheme.onSurfaceVariant
        : available
        ? const Color(0xFF168347)
        : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, start: 4),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: available == null ? null : FontWeight.w700)),
    );
  }

  Widget _roleCard({
    required String value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final selected = _role == value;
    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: InkWell(
        onTap: _isSubmitting ? null : () => setState(() => _role = value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF7ED) : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Radio<String>(value: value, groupValue: _role, onChanged: _isSubmitting ? null : (next) => setState(() => _role = next!)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isRegistering ? 'أنشئ حسابك' : 'تسجيل الدخول')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 22),
            Text(_isRegistering ? 'مرحباً بك في تجارتي' : 'أهلاً بعودتك', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              _isRegistering ? 'أنشئ حسابك ثم اختر نوعه.' : 'أدخل بياناتك للمتابعة.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_isRegistering) ...[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                      validator: (value) => (value?.trim().length ?? 0) < 2 ? 'اكتب اسماً صحيحاً.' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        suffixIcon: _usernameAvailable == true ? const Icon(Icons.check_circle_rounded, color: Color(0xFF168347)) : null,
                      ),
                      onChanged: (value) => _queueAvailability('username', value),
                      validator: (value) => _usernamePattern.hasMatch(value?.trim() ?? '') ? null : 'اسم المستخدم من 3 إلى 30 حرفاً أو رقماً.',
                    ),
                    _availabilityNote(_usernameFeedback, _usernameAvailable),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف',
                      suffixIcon: _isRegistering && _phoneAvailable == true ? const Icon(Icons.check_circle_rounded, color: Color(0xFF168347)) : null,
                    ),
                    onChanged: _isRegistering ? (value) => _queueAvailability('phone', value) : null,
                    validator: (value) => _phonePattern.hasMatch(value?.trim() ?? '') ? null : 'أدخل رقم هاتف من 7 إلى 18 رقماً.',
                  ),
                  if (_isRegistering) _availabilityNote(_phoneFeedback, _phoneAvailable),
                  if (_isRegistering) ...[
                    const SizedBox(height: 22),
                    Align(alignment: AlignmentDirectional.centerStart, child: Text('اختر نوع الحساب', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                    const SizedBox(height: 8),
                    _roleCard(value: 'customer', icon: Icons.person_rounded, title: 'عميل', description: 'تسوّق، احفظ العناوين، وتابع طلباتك.'),
                    _roleCard(value: 'merchant', icon: Icons.storefront_rounded, title: 'تاجر', description: 'أنشئ متجرك وأدر منتجاتك ومبيعاتك.'),
                    _roleCard(value: 'courier', icon: Icons.local_shipping_rounded, title: 'عامل توصيل', description: 'تابع مهام التوصيل والمحفظة.'),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    validator: (value) => (value?.length ?? 0) < 10 ? 'كلمة المرور 10 أحرف على الأقل.' : null,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isRegistering ? 'إنشاء الحساب' : 'دخول آمن'),
            ),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() {
                      _isRegistering = !_isRegistering;
                      _error = null;
                      _usernameFeedback = null;
                      _phoneFeedback = null;
                      _usernameAvailable = null;
                      _phoneAvailable = null;
                    }),
              child: Text(_isRegistering ? 'لديك حساب بالفعل؟ سجّل الدخول' : 'ليس لديك حساب؟ أنشئ حساباً'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';

/// A role-specific, private verification workflow for merchants and couriers.
/// The pending status is set in the current screen immediately after the API
/// accepts the request; the user never needs to sign out or restart the app.
final class AccountVerificationPage extends StatefulWidget {
  const AccountVerificationPage({super.key, required this.roleCode});

  final String roleCode;

  @override
  State<AccountVerificationPage> createState() => _AccountVerificationPageState();
}

final class _AccountVerificationPageState extends State<AccountVerificationPage> {
  late Future<List<Map<String, dynamic>>> _future;
  XFile? _identity;
  XFile? _selfie;
  bool _submitting = false;
  String? _immediateStatus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(context).loadMyVerificationRequests();
  }

  String get _roleLabel => switch (widget.roleCode) {
    'merchant' => 'التاجر',
    'courier' => 'عامل التوصيل',
    _ => 'الحساب',
  };

  String _statusOf(List<Map<String, dynamic>> items) {
    if (_immediateStatus != null) return _immediateStatus!;
    for (final item in items) {
      if (item['role_code'] == widget.roleCode) {
        return item['verification_status'] as String? ?? 'not_submitted';
      }
    }
    return 'not_submitted';
  }

  Future<void> _pick(bool isIdentity) async {
    final file = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() {
      if (isIdentity) {
        _identity = file;
      } else {
        _selfie = file;
      }
    });
  }

  Future<void> _submit() async {
    final identity = _identity;
    final selfie = _selfie;
    if (identity == null || selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر صورة الهوية والصورة الشخصية أولاً.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await AppScope.of(context).submitVerificationRequest(
        roleCode: widget.roleCode,
        identity: identity,
        selfie: selfie,
      );
      if (!mounted) return;
      setState(() => _immediateStatus = 'pending');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال التوثيق وهو الآن قيد المراجعة.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال طلب التوثيق الآن.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('توثيق حساب $_roleLabel')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is ApiException
                  ? error.message
                  : 'تعذر تحميل حالة التوثيق.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => setState(
                          () => _future = AppScope.of(context)
                              .loadMyVerificationRequests(),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final status = _statusOf(snapshot.data ?? const []);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _VerificationStatusCard(status: status, roleLabel: _roleLabel),
                const SizedBox(height: 18),
                if (status != 'pending' && status != 'verified') ...[
                  Text(
                    'ملفات التوثيق',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تُرفع الوثائق كملفات خاصة ولا تظهر للمستخدمين الآخرين. اختر صور JPG أو PNG أو WebP من الاستوديو.',
                  ),
                  const SizedBox(height: 14),
                  _PrivateImagePicker(
                    label: 'صورة الهوية',
                    file: _identity,
                    onPick: () => _pick(true),
                  ),
                  const SizedBox(height: 10),
                  _PrivateImagePicker(
                    label: 'صورة شخصية',
                    file: _selfie,
                    onPick: () => _pick(false),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(_submitting ? 'جارٍ إرسال التوثيق…' : 'إرسال طلب التوثيق'),
                  ),
                ],
              ],
            );
          },
        ),
      );
}

final class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard({required this.status, required this.roleLabel});

  final String status;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final (title, body, icon, color) = switch (status) {
      'pending' => (
          'التوثيق قيد المراجعة',
          'تم استلام بيانات توثيق $roleLabel. لا تحتاج إلى إرسال الطلب مرة أخرى.',
          Icons.hourglass_top_rounded,
          Colors.orange,
        ),
      'verified' => (
          'الحساب موثق',
          'تم اعتماد توثيق $roleLabel بنجاح.',
          Icons.verified_rounded,
          Colors.green,
        ),
      'rejected' => (
          'يمكنك إعادة إرسال التوثيق',
          'تم رفض الطلب السابق. اختر صوراً أوضح ثم أرسل طلباً جديداً.',
          Icons.restart_alt_rounded,
          Colors.redAccent,
        ),
      _ => (
          'لم يتم إرسال طلب توثيق بعد',
          'أكمل الملفين التاليين لإرسال طلب توثيق $roleLabel.',
          Icons.shield_outlined,
          Theme.of(context).colorScheme.primary,
        ),
    };
    return Card(
      color: color.withOpacity(.09),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PrivateImagePicker extends StatelessWidget {
  const _PrivateImagePicker({
    required this.label,
    required this.file,
    required this.onPick,
  });

  final String label;
  final XFile? file;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(file == null ? 'اختر $label من الاستوديو' : '$label جاهزة للرفع'),
      );
}

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Privileged, server-authoritative user management. Account deletion is soft
/// and the API revokes active sessions before the user disappears from lists.
final class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

final class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  bool _loaded = false;
  String _role = '';
  String _status = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      AppScope.of(context)
          .loadAdminUsers(search: _search.text, role: _role, status: _status);

  void _reload() => setState(() => _future = _load());

  Future<void> _edit([Map<String, dynamic>? user]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AdminUserDialog(user: user),
    );
    if (result == true && mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الحساب بشكل آمن؟'),
        content: Text(
          'سيُعطّل حساب ${user['full_name'] ?? 'المستخدم'} وتُلغى جلساته، دون حذف الفواتير أو السجل المالي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف آمن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppScope.of(context).deleteAdminUser(user['public_id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تعطيل الحساب وإلغاء جلساته.')),
        );
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('إدارة المستخدمين'),
      actions: [
        IconButton(
          tooltip: 'إضافة مستخدم',
          onPressed: () => _edit(),
          icon: const Icon(Icons.person_add_alt_1_rounded),
        ),
      ],
      bottom: adminControlBottom(context, 'users'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو المستخدم أو الهاتف',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'بحث',
                onPressed: _reload,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('كل الأدوار')),
                    DropdownMenuItem(value: 'customer', child: Text('عميل')),
                    DropdownMenuItem(value: 'merchant', child: Text('تاجر')),
                    DropdownMenuItem(
                      value: 'courier',
                      child: Text('عامل توصيل'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('مدير')),
                  ],
                  onChanged: (value) => setState(() => _role = value ?? ''),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('النشطة')),
                    DropdownMenuItem(value: 'active', child: Text('نشط')),
                    DropdownMenuItem(value: 'restricted', child: Text('مقيّد')),
                    DropdownMenuItem(value: 'suspended', child: Text('معلّق')),
                    DropdownMenuItem(value: 'deleted', child: Text('محذوفة')),
                  ],
                  onChanged: (value) => setState(() => _status = value ?? ''),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : 'تعذر تحميل المستخدمين.';
                return Center(
                  child: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(message),
                  ),
                );
              }
              final users = snapshot.data ?? const [];
              if (users.isEmpty) {
                return const Center(child: Text('لا توجد حسابات مطابقة.'));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _UserCard(
                    user: users[index],
                    onEdit: () => _edit(users[index]),
                    onDelete: () => _delete(users[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

final class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final roles = List<String>.from(user['roles'] as List? ?? const []);
    final status = user['account_status'] as String? ?? 'active';
    final merchantStatus = user['merchant_verification_status'] as String?;
    final courierStatus = user['courier_verification_status'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(_initial(user['full_name'] as String?)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['full_name'] as String? ?? 'مستخدم',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@${user['username'] ?? '—'} · ${user['phone'] ?? '—'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'delete', child: Text('حذف آمن')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                _Chip(
                  label: _accountStatus(status),
                  active: status == 'active',
                ),
                ...roles.map((role) => _Chip(label: _roleName(role))),
                if (merchantStatus != null)
                  _Chip(label: 'تاجر: ${_verificationStatus(merchantStatus)}'),
                if (courierStatus != null)
                  _Chip(label: 'توصيل: ${_verificationStatus(courierStatus)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initial(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim().substring(0, 1) : 'ت';
  String _roleName(String value) => switch (value) {
    'customer' => 'عميل',
    'merchant' => 'تاجر',
    'courier' => 'عامل توصيل',
    'admin' => 'مدير',
    _ => value,
  };
  String _accountStatus(String value) => switch (value) {
    'active' => 'نشط',
    'restricted' => 'مقيّد',
    'suspended' => 'معلّق',
    'deleted' => 'محذوف',
    _ => value,
  };
  String _verificationStatus(String value) => switch (value) {
    'verified' => 'موثّق',
    'pending' => 'قيد المراجعة',
    'rejected' => 'مرفوض',
    _ => 'غير موثق',
  };
}

final class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.active = false});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(label),
    backgroundColor: active
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    side: BorderSide.none,
  );
}

final class _AdminUserDialog extends StatefulWidget {
  const _AdminUserDialog({this.user});
  final Map<String, dynamic>? user;

  @override
  State<_AdminUserDialog> createState() => _AdminUserDialogState();
}

final class _AdminUserDialogState extends State<_AdminUserDialog> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _phone;
  final _password = TextEditingController();
  late Set<String> _roles;
  late String _status;
  late bool _merchantVerified;
  late bool _courierVerified;
  bool _saving = false;

  bool get _editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user?['full_name'] as String? ?? '');
    _username = TextEditingController(text: user?['username'] as String? ?? '');
    _phone = TextEditingController(text: user?['phone'] as String? ?? '');
    _roles = Set<String>.from(user?['roles'] as List? ?? const ['customer']);
    _status = user?['account_status'] as String? ?? 'active';
    _merchantVerified = user?['merchant_verification_status'] == 'verified';
    _courierVerified = user?['courier_verification_status'] == 'verified';
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2 ||
        _username.text.trim().length < 3 ||
        _phone.text.trim().isEmpty ||
        _roles.isEmpty ||
        (!_editing && _password.text.length < 10)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أكمل الحقول المطلوبة واختر دوراً واحداً على الأقل.'),
        ),
      );
      return;
    }
    final input = <String, dynamic>{
      'full_name': _name.text.trim(),
      'username': _username.text.trim(),
      'phone': _phone.text.trim(),
      'roles': _roles.toList(),
      'account_status': _status,
      if (_roles.contains('merchant')) 'merchant_verified': _merchantVerified,
      if (_roles.contains('courier')) 'courier_verified': _courierVerified,
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    setState(() => _saving = true);
    try {
      if (_editing) {
        await AppScope.of(context)
            .updateAdminUser(widget.user!['public_id'] as String, input);
      } else {
        await AppScope.of(context).createAdminUser(input);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'تعديل المستخدم' : 'إضافة مستخدم'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _username,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'اسم المستخدم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _editing
                    ? 'كلمة مرور جديدة (اختيارية)'
                    : 'كلمة المرور',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'حالة الحساب'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('نشط')),
                DropdownMenuItem(value: 'restricted', child: Text('مقيّد')),
                DropdownMenuItem(value: 'suspended', child: Text('معلّق')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'الأدوار',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            ...const [
              ('customer', 'عميل'),
              ('merchant', 'تاجر'),
              ('courier', 'عامل توصيل'),
              ('admin', 'مدير'),
            ].map(
              (role) => CheckboxListTile(
                value: _roles.contains(role.$1),
                contentPadding: EdgeInsets.zero,
                title: Text(role.$2),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _roles.add(role.$1);
                        } else {
                          _roles.remove(role.$1);
                        }
                      }),
              ),
            ),
            if (_roles.contains('merchant'))
              SwitchListTile.adaptive(
                value: _merchantVerified,
                contentPadding: EdgeInsets.zero,
                title: const Text('اعتماد توثيق التاجر'),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _merchantVerified = value),
              ),
            if (_roles.contains('courier'))
              SwitchListTile.adaptive(
                value: _courierVerified,
                contentPadding: EdgeInsets.zero,
                title: const Text('اعتماد توثيق عامل التوصيل'),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _courierVerified = value),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(_editing ? 'حفظ' : 'إنشاء'),
      ),
    ],
  );
}

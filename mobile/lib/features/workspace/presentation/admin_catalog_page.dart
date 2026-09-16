import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Store and product catalogue controls kept parallel with the web admin route.
/// Categories are soft-managed through their active flag, preserving products
/// and store history that already reference them.
final class AdminCatalogPage extends StatelessWidget {
  const AdminCatalogPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('كتالوج المتاجر والمنتجات'),
            bottom: adminTabbedBottom(
              context,
              'catalog',
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.storefront_outlined), text: 'تصنيفات المتاجر'),
                  Tab(icon: Icon(Icons.inventory_2_outlined), text: 'تصنيفات المنتجات'),
                ],
              ),
            ),
          ),
          body: const TabBarView(
            children: [
              _AdminCatalogTypeTab(type: 'store', title: 'تصنيفات المتاجر'),
              _AdminCatalogTypeTab(type: 'product', title: 'تصنيفات المنتجات'),
            ],
          ),
        ),
      );
}

final class _AdminCatalogTypeTab extends StatefulWidget {
  const _AdminCatalogTypeTab({required this.type, required this.title});
  final String type;
  final String title;

  @override
  State<_AdminCatalogTypeTab> createState() => _AdminCatalogTypeTabState();
}

final class _AdminCatalogTypeTabState extends State<_AdminCatalogTypeTab> {
  final _search = TextEditingController();
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      AppScope.of(context).loadAdminCatalogCategories(widget.type);

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(
    List<Map<String, dynamic>> siblings, [
    Map<String, dynamic>? category,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CatalogCategoryDialog(
        type: widget.type,
        category: category,
        siblings: siblings,
      ),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'تعذر تحميل التصنيفات.';
            return Center(
              child: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(message),
              ),
            );
          }
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = _search.text.trim().toLowerCase();
          final visible = all
              .where((item) => query.isEmpty || '${item['name'] ?? ''} ${item['description'] ?? ''}'.toLowerCase().contains(query))
              .toList(growable: false);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'ابحث في ${widget.title}',
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'إضافة تصنيف',
                      onPressed: () => _edit(all),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 8),
                child: Text(
                  '${visible.length} تصنيف · التعديل والتعطيل لا يحذفان السجل أو العناصر المرتبطة به.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(
                              height: 240,
                              child: Center(child: Text('لا توجد تصنيفات مطابقة.')),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            final active = item['is_active'] == true;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: active
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    widget.type == 'store'
                                        ? Icons.storefront_outlined
                                        : Icons.inventory_2_outlined,
                                  ),
                                ),
                                title: Text(
                                  item['name'] as String? ?? 'تصنيف',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  '${item['description'] ?? 'لا يوجد وصف'}\nترتيب ${item['sort_order'] ?? 0}${item['parent_public_id'] != null ? ' · تصنيف فرعي' : ''}',
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      active ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      size: 18,
                                      color: active ? Theme.of(context).colorScheme.primary : null,
                                    ),
                                    const SizedBox(height: 2),
                                    const Icon(Icons.edit_outlined, size: 18),
                                  ],
                                ),
                                onTap: () => _edit(all, item),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      );
}

final class _CatalogCategoryDialog extends StatefulWidget {
  const _CatalogCategoryDialog({
    required this.type,
    required this.siblings,
    this.category,
  });
  final String type;
  final List<Map<String, dynamic>> siblings;
  final Map<String, dynamic>? category;

  @override
  State<_CatalogCategoryDialog> createState() => _CatalogCategoryDialogState();
}

final class _CatalogCategoryDialogState extends State<_CatalogCategoryDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _sort;
  late String _parentId;
  late bool _active;
  bool _saving = false;
  XFile? _image;

  bool get _editing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final item = widget.category;
    _name = TextEditingController(text: item?['name'] as String? ?? '');
    _description = TextEditingController(text: item?['description'] as String? ?? '');
    _sort = TextEditingController(text: '${item?['sort_order'] ?? 0}');
    _parentId = item?['parent_public_id'] as String? ?? '';
    _active = item?['is_active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسم التصنيف يجب أن يحتوي حرفين على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final imageId = _image == null
          ? null
          : await AppScope.of(context).uploadAdminPublicMedia(_image!);
      await AppScope.of(context).saveAdminCatalogCategory(
        type: widget.type,
        publicId: widget.category?['public_id'] as String?,
        body: {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'sort_order': int.tryParse(_sort.text.trim()) ?? 0,
          'parent_public_id': _parentId,
          'is_active': _active,
          if (imageId != null) 'image_media_id': imageId,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownId = widget.category?['public_id'] as String?;
    final parents = widget.siblings.where((item) => item['public_id'] != ownId).toList(growable: false);
    return AlertDialog(
      title: Text(_editing ? 'تفاصيل وتعديل التصنيف' : 'تصنيف جديد'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'اسم التصنيف *')),
              const SizedBox(height: 8),
              TextField(controller: _description, maxLength: 500, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'الوصف')),
              const SizedBox(height: 8),
              TextField(controller: _sort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ترتيب الظهور')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _parentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'التصنيف الأب (اختياري)'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('بدون تصنيف أب')),
                  ...parents.map((item) => DropdownMenuItem(value: item['public_id'] as String? ?? '', child: Text(item['name'] as String? ?? 'تصنيف'))),
                ],
                onChanged: _saving ? null : (value) => setState(() => _parentId = value ?? ''),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final image = await ImageUploadPolicy.pick(ImageSource.gallery);
                        if (image != null && mounted) setState(() => _image = image);
                      },
                icon: Icon(_image == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline_rounded),
                label: Text(_image == null ? 'إرفاق صورة التصنيف (اختياري)' : 'تم اختيار صورة التصنيف — تغييرها'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: _saving ? null : (value) => setState(() => _active = value),
                title: const Text('إتاحة التصنيف للمستخدمين'),
                subtitle: const Text('إيقاف التصنيف يحافظ على بياناته وعناصره السابقة.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ')),
      ],
    );
  }
}

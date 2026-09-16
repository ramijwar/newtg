import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';

/// Merchants can manage only profile banners; administrators manage only the
/// directory carousel. The API independently enforces that separation.
final class StoreBannerManagementPage extends StatefulWidget {
  const StoreBannerManagementPage({super.key, required this.admin});
  final bool admin;
  @override State<StoreBannerManagementPage> createState() => _StoreBannerManagementPageState();
}

final class _StoreBannerManagementPageState extends State<StoreBannerManagementPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, dynamic>>> _load() => AppScope.of(context).loadStoreBanners(admin: widget.admin);
  void _reload() => setState(() => _future = _load());
  Future<void> _edit([Map<String, dynamic>? banner]) async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _BannerEditor(admin: widget.admin, banner: banner));
    if (saved == true && mounted) _reload();
  }
  Future<void> _delete(Map<String, dynamic> banner) async {
    final id = banner['public_id'] as String? ?? ''; if (id.isEmpty) return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف البنر؟'), content: const Text('سيُحذف البنر من العرض العام بشكل آمن.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
    if (yes != true || !mounted) return;
    try { await AppScope.of(context).deleteStoreBanner(admin: widget.admin, bannerId: id); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف البنر.'))); _reload(); } }
    on ApiException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.admin ? 'بنرات دليل المتاجر' : 'إعلانات متجري'), actions: [IconButton(onPressed: _reload, tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('إضافة بنر')),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل البنرات.', textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة'))])));
      final items = snapshot.data ?? const <Map<String, dynamic>>[];
      if (items.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(widget.admin ? 'لا توجد بنرات في أعلى دليل المتاجر.' : 'لا توجد إعلانات داخل متجرك بعد.', textAlign: TextAlign.center)));
      return RefreshIndicator(onRefresh: () async => _reload(), child: ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (context, index) {
        final item = items[index]; final media = item['media_public_id'] as String?;
        return Card(clipBehavior: Clip.antiAlias, child: Row(children: [SizedBox(width: 110, height: 82, child: media?.isNotEmpty == true ? CachedMediaImage(mediaPublicId: media!, fit: BoxFit.cover) : const ColoredBox(color: Color(0xFFE7EEE9), child: Icon(Icons.image_outlined))), Expanded(child: Padding(padding: const EdgeInsets.all(11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['title'] as String? ?? 'بنر بلا عنوان', style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(_destinationLabel(item['destination_type'] as String? ?? 'none'), style: Theme.of(context).textTheme.bodySmall), Text('${item['is_active'] != false && item['is_active'] != 0 ? 'ظاهر' : 'مخفي'} · ترتيب ${item['sort_order'] ?? 0}', style: Theme.of(context).textTheme.bodySmall)]))), PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') _edit(item); else _delete(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('تعديل')), PopupMenuItem(value: 'delete', child: Text('حذف'))]) ]));
      }));
    }),
  );
}
String _destinationLabel(String type) => switch (type) {'product' => 'يفتح منتجاً', 'store' => 'يفتح متجراً', 'external' => 'يفتح رابطاً خارجياً', _ => 'دون وجهة'};

final class _BannerEditor extends StatefulWidget { const _BannerEditor({required this.admin, this.banner}); final bool admin; final Map<String, dynamic>? banner; @override State<_BannerEditor> createState() => _BannerEditorState(); }
final class _BannerEditorState extends State<_BannerEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _body, _product, _store, _url, _sort, _starts, _ends;
  String _type = 'none'; bool _active = true, _saving = false; XFile? _image; Future<Uint8List>? _preview;
  @override void initState() { super.initState(); final b = widget.banner ?? const <String, dynamic>{}; _title=TextEditingController(text:b['title'] as String? ?? ''); _body=TextEditingController(text:b['body'] as String? ?? ''); _product=TextEditingController(text:b['destination_product_id'] as String? ?? ''); _store=TextEditingController(text:b['destination_store_id'] as String? ?? ''); _url=TextEditingController(text:b['external_url'] as String? ?? ''); _sort=TextEditingController(text:'${b['sort_order']??0}'); _starts=TextEditingController(text:_dateText(b['starts_at'])); _ends=TextEditingController(text:_dateText(b['ends_at'])); _type=b['destination_type'] as String? ?? 'none'; _active=b['is_active'] != false; }
  @override void dispose() { for (final c in [_title,_body,_product,_store,_url,_sort,_starts,_ends]) { c.dispose(); } super.dispose(); }
  String _dateText(Object? value) { if (value == null) return ''; final text = value.toString().replaceFirst('T',' '); return text.substring(0, text.length < 16 ? text.length : 16); }
  Future<void> _pick() async { final image=await ImageUploadPolicy.pick(ImageSource.gallery); if(image!=null&&mounted)setState((){_image=image;_preview=image.readAsBytes();}); }
  Future<void> _save() async { if (!_form.currentState!.validate()) return; if(widget.banner==null&&_image==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اختر صورة البنر أولاً.')));return;} setState(()=>_saving=true); try { await AppScope.of(context).saveStoreBanner(admin:widget.admin,bannerId:widget.banner?['public_id'] as String?,image:_image,values:{'title':_title.text.trim(),'body':_body.text.trim(),'sort_order':int.tryParse(_sort.text)??0,'is_active':_active,'destination_type':_type,'destination_product_public_id':_type=='product'?_product.text.trim():null,'destination_store_public_id':_type=='store'?_store.text.trim():null,'external_url':_type=='external'?_url.text.trim():null,'starts_at':_starts.text.trim(),'ends_at':_ends.text.trim()}); if(mounted)Navigator.pop(context,true); } on ApiException catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message))); } finally { if(mounted)setState(()=>_saving=false); } }
  @override
  Widget build(BuildContext context) {
    final existing = widget.banner?['media_public_id'] as String?;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.banner == null ? 'إضافة بنر' : 'تعديل البنر', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _saving ? null : _pick,
                  child: Container(
                    height: 130,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: const Color(0xFFE7EEE9), borderRadius: BorderRadius.circular(13)),
                    child: _preview != null
                      ? FutureBuilder<Uint8List>(future: _preview, builder: (_, snapshot) => snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover) : const Center(child: CircularProgressIndicator()))
                      : existing?.isNotEmpty == true
                        ? CachedMediaImage(mediaPublicId: existing!, fit: BoxFit.cover)
                        : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate_outlined, size: 35), Text('اختر صورة البنر')])),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'عنوان مختصر')),
                TextFormField(controller: _body, maxLength: 240, decoration: const InputDecoration(labelText: 'نص توضيحي')),
                Row(children: [
                  Expanded(child: TextFormField(controller: _sort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الترتيب'), validator: (value) { final number = int.tryParse(value ?? ''); return number == null || number < 0 || number > 999 ? 'بين 0 و999' : null; })),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'وجهة النقر'), items: const [DropdownMenuItem(value: 'none', child: Text('بلا وجهة')), DropdownMenuItem(value: 'product', child: Text('منتج')), DropdownMenuItem(value: 'store', child: Text('متجر')), DropdownMenuItem(value: 'external', child: Text('رابط HTTPS'))], onChanged: _saving ? null : (value) => setState(() => _type = value ?? 'none'))),
                ]),
                if (_type == 'product') TextFormField(controller: _product, decoration: const InputDecoration(labelText: 'معرف المنتج العام'), validator: (value) => value!.trim().isEmpty ? 'اكتب معرف المنتج.' : null),
                if (_type == 'store') TextFormField(controller: _store, decoration: const InputDecoration(labelText: 'معرف المتجر العام'), validator: (value) => value!.trim().isEmpty ? 'اكتب معرف المتجر.' : null),
                if (_type == 'external') TextFormField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط HTTPS'), validator: (value) { final uri = Uri.tryParse(value?.trim() ?? ''); return uri == null || uri.scheme != 'https' || uri.host.isEmpty ? 'اكتب رابط HTTPS صالحاً.' : null; }),
                TextFormField(controller: _starts, decoration: const InputDecoration(labelText: 'يبدأ في (اختياري)', hintText: '2026-12-31 09:00')),
                TextFormField(controller: _ends, decoration: const InputDecoration(labelText: 'ينتهي في (اختياري)', hintText: '2026-12-31 21:00')),
                SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _active, onChanged: _saving ? null : (value) => setState(() => _active = value), title: const Text('إظهار البنر')),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ البنر')),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';

/// Owner-only update flow. The API independently rejects updates to listings
/// that are published, reserved or sold, so the client never bypasses policy.
final class MarketplaceListingUpdatePage extends StatefulWidget {
  const MarketplaceListingUpdatePage({super.key, required this.listingId, required this.title});
  final String listingId;
  final String title;
  @override
  State<MarketplaceListingUpdatePage> createState() => _MarketplaceListingUpdatePageState();
}

final class _MarketplaceListingUpdatePageState extends State<MarketplaceListingUpdatePage> {
  Future<dynamic>? _future;
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  bool _saving = false;
  bool _submit = false;
  XFile? _image;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _future ??= AppScope.of(context).loadListingDetails(widget.listingId); }
  @override
  void dispose() { _title.dispose(); _description.dispose(); _price.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).updateMarketplaceListing(listingId: widget.listingId, title: _title.text, description: _description.text, priceAmount: _price.text, submitForReview: _submit);
      if (_image != null) {
        await AppScope.of(context).replaceMarketplaceListingImage(
          listingId: widget.listingId,
          image: _image!,
        );
      }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات.'))); Navigator.of(context).pop(true); }
    } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعديل الإعلان')),
    body: FutureBuilder<dynamic>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (!snapshot.hasData) return Center(child: OutlinedButton.icon(onPressed: () => setState(() => _future = AppScope.of(context).loadListingDetails(widget.listingId)), icon: const Icon(Icons.refresh_rounded), label: const Text('تعذر تحميل الإعلان')));
      final listing = snapshot.data.listing;
      if (_title.text.isEmpty) { _title.text = listing.title; _description.text = listing.description ?? ''; _price.text = listing.priceAmount?.toString() ?? ''; }
      return Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          onPressed: () async {
            final image = await ImageUploadPolicy.pick(ImageSource.gallery);
            if (image != null && mounted) setState(() => _image = image);
          },
          icon: Icon(_image == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline_rounded),
          label: Text(_image == null ? 'تغيير صورة الإعلان' : 'تم اختيار صورة جديدة'),
        ),
        const SizedBox(height: 10),
        TextFormField(controller: _title, maxLength: 180, decoration: const InputDecoration(labelText: 'العنوان *'), validator: (value) => (value?.trim().length ?? 0) < 4 ? 'اكتب عنواناً صحيحاً.' : null), const SizedBox(height: 9),
        TextFormField(controller: _description, minLines: 4, maxLines: 8, maxLength: 5000, decoration: const InputDecoration(labelText: 'الوصف *'), validator: (value) => (value?.trim().length ?? 0) < 10 ? 'اكتب وصفاً صحيحاً.' : null), const SizedBox(height: 9),
        TextFormField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر (اختياري)'), validator: (value) => value == null || value.trim().isEmpty || num.tryParse(value.trim()) != null ? null : 'أدخل سعراً صحيحاً.'),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إرسال للمراجعة بعد الحفظ'), subtitle: const Text('يخضع الإعلان لسياسة النشر المفعلة في الحراج.'), value: _submit, onChanged: (value) => setState(() => _submit = value)), const SizedBox(height: 18),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ التعديلات')),
      ]));
    }),
  );
}

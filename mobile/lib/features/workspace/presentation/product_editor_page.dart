import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import '../../catalog/domain/catalog_models.dart';

final class ProductEditorPage extends StatefulWidget {
  const ProductEditorPage({
    super.key,
    required this.currencyCode,
    required this.canPublish,
    this.product,
  });

  final String currencyCode;
  final bool canPublish;
  final StoreProduct? product;

  bool get isEditing => product != null;

  @override
  State<ProductEditorPage> createState() => _ProductEditorPageState();
}

final class _ProductEditorPageState extends State<ProductEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _sku;
  late final TextEditingController _preorderLeadDays;
  late final TextEditingController _preorderMinimum;
  late final TextEditingController _preorderMaximum;
  late final TextEditingController _salePrice;
  late String _status;
  late String _fulfillmentMode;
  late bool _specialOffer;
  DateTime? _saleEndsAt;
  XFile? _image;
  Future<Uint8List>? _preview;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final item = widget.product;
    _name = TextEditingController(text: item?.name ?? '');
    _description = TextEditingController(text: item?.description ?? '');
    _price = TextEditingController(text: item?.price.toString() ?? '');
    _stock = TextEditingController(text: item?.stockQuantity.toString() ?? '0');
    _sku = TextEditingController(text: item?.sku ?? '');
    _preorderLeadDays = TextEditingController(text: item?.preorderLeadDays?.toString() ?? '');
    _preorderMinimum = TextEditingController(text: item?.preorderMinQuantity?.toString() ?? '');
    _preorderMaximum = TextEditingController(text: item?.preorderMaxQuantity?.toString() ?? '');
    _salePrice = TextEditingController(text: item?.salePrice?.toString() ?? '');
    _status = item?.productStatus ?? (widget.canPublish ? 'active' : 'draft');
    _fulfillmentMode = item?.fulfillmentMode == 'preorder' ? 'preorder' : 'retail';
    _specialOffer = item?.isSpecialOffer ?? false;
    _saleEndsAt = DateTime.tryParse(item?.saleEndsAt ?? '');
    if (!widget.canPublish && _status == 'active') _status = 'draft';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    _sku.dispose();
    _preorderLeadDays.dispose();
    _preorderMinimum.dispose();
    _preorderMaximum.dispose();
    _salePrice.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        _image = image;
        _preview = image.readAsBytes();
      });
    }
  }

  Future<void> _pickOfferEnd() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _saleEndsAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      setState(() => _saleEndsAt = DateTime(selected.year, selected.month, selected.day, 23, 59));
    }
  }

  void _error(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.canPublish && _status == 'active') {
      _error('فعّل المتجر أولاً قبل نشر المنتج.');
      return;
    }
    final price = num.parse(_price.text.trim());
    int? preorderLeadDays;
    int? preorderMinimum;
    int? preorderMaximum;
    if (_fulfillmentMode == 'preorder') {
      preorderLeadDays = int.tryParse(_preorderLeadDays.text.trim());
      preorderMinimum = int.tryParse(_preorderMinimum.text.trim());
      preorderMaximum = _preorderMaximum.text.trim().isEmpty ? null : int.tryParse(_preorderMaximum.text.trim());
      if (preorderLeadDays == null || preorderLeadDays < 1 || preorderLeadDays > 365 || preorderMinimum == null || preorderMinimum < 1) {
        _error('أدخل مدة تجهيز وكمية دنيا صالحتين للطلب المسبق.');
        return;
      }
      if (preorderMaximum != null && (preorderMaximum < preorderMinimum || preorderMaximum < 1)) {
        _error('الكمية القصوى يجب ألا تقل عن الكمية الدنيا.');
        return;
      }
    }
    num? salePrice;
    if (_specialOffer) {
      salePrice = num.tryParse(_salePrice.text.trim());
      if (salePrice == null || salePrice > price || _saleEndsAt == null) {
        _error('حدد سعراً مخفضاً ووقت انتهاء للعرض الخاص.');
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final common = <String, dynamic>{
        'name': _name.text,
        'description': _description.text,
        'price': price,
        'stockQuantity': int.parse(_stock.text.trim()),
        'currencyCode': widget.currencyCode,
        'fulfillmentMode': _fulfillmentMode,
        'preorderMinQuantity': preorderMinimum,
        'preorderMaxQuantity': preorderMaximum,
        'preorderLeadDays': preorderLeadDays,
        'isSpecialOffer': _specialOffer,
        'salePrice': salePrice,
        'saleEndsAt': _saleEndsAt,
      };
      if (widget.isEditing) {
        await AppScope.of(context).updateMerchantProduct(
          productId: widget.product!.publicId,
          name: common['name'] as String,
          description: common['description'] as String,
          price: common['price'] as num,
          stockQuantity: common['stockQuantity'] as int,
          currencyCode: common['currencyCode'] as String,
          productStatus: _status,
          sku: _sku.text,
          fulfillmentMode: common['fulfillmentMode'] as String,
          preorderMinQuantity: common['preorderMinQuantity'] as int?,
          preorderMaxQuantity: common['preorderMaxQuantity'] as int?,
          preorderLeadDays: common['preorderLeadDays'] as int?,
          isSpecialOffer: common['isSpecialOffer'] as bool,
          salePrice: common['salePrice'] as num?,
          saleEndsAt: common['saleEndsAt'] as DateTime?,
          image: _image,
        );
      } else {
        await AppScope.of(context).createMerchantProduct(
          name: common['name'] as String,
          description: common['description'] as String,
          price: common['price'] as num,
          stockQuantity: common['stockQuantity'] as int,
          currencyCode: common['currencyCode'] as String,
          publish: _status == 'active',
          fulfillmentMode: common['fulfillmentMode'] as String,
          preorderMinQuantity: common['preorderMinQuantity'] as int?,
          preorderMaxQuantity: common['preorderMaxQuantity'] as int?,
          preorderLeadDays: common['preorderLeadDays'] as int?,
          isSpecialOffer: common['isSpecialOffer'] as bool,
          salePrice: common['salePrice'] as num?,
          saleEndsAt: common['saleEndsAt'] as DateTime?,
          image: _image,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _error(error.message);
    } on FormatException catch (error) {
      if (mounted) _error(error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('أرشفة المنتج؟'),
        content: const Text('سيُخفى المنتج من المتجر ولا يمكن التراجع عن الأرشفة من التطبيق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أرشفة')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await AppScope.of(context).archiveMerchantProduct(widget.product!.publicId);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _error(error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.isEditing ? 'تعديل المنتج' : 'إضافة منتج')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          TextFormField(controller: _name, maxLength: 180, decoration: const InputDecoration(labelText: 'اسم المنتج'), validator: (value) => (value?.trim().length ?? 0) < 2 ? 'اكتب اسماً من حرفين على الأقل.' : null),
          const SizedBox(height: 10),
          TextFormField(controller: _description, maxLength: 5000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'وصف المنتج (اختياري)')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextFormField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'السعر (${widget.currencyCode})'), validator: _priceValidator)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون'), validator: _stockValidator)),
          ]),
          const SizedBox(height: 10),
          TextFormField(controller: _sku, maxLength: 80, decoration: const InputDecoration(labelText: 'رمز المنتج (اختياري)'), validator: _skuValidator),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('طريقة البيع والعرض', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _fulfillmentMode,
                  decoration: const InputDecoration(labelText: 'نمط البيع'),
                  items: const [
                    DropdownMenuItem(value: 'retail', child: Text('بيع بالتجزئة')),
                    DropdownMenuItem(value: 'preorder', child: Text('طلب مسبق')),
                  ],
                  onChanged: _submitting ? null : (value) => setState(() => _fulfillmentMode = value ?? 'retail'),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _fulfillmentMode != 'preorder'
                      ? const SizedBox.shrink()
                      : Padding(
                          key: const ValueKey('preorder-fields'),
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(children: [
                            TextFormField(controller: _preorderLeadDays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدة التجهيز بالأيام'), validator: _positiveIntegerValidator),
                            const SizedBox(height: 9),
                            Row(children: [
                              Expanded(child: TextFormField(controller: _preorderMinimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية الدنيا'), validator: _positiveIntegerValidator)),
                              const SizedBox(width: 10),
                              Expanded(child: TextFormField(controller: _preorderMaximum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية القصوى (اختيارية)'), validator: _optionalPositiveIntegerValidator)),
                            ]),
                          ]),
                        ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _specialOffer,
                  onChanged: _submitting ? null : (value) => setState(() => _specialOffer = value),
                  title: const Text('عرض خاص'),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: !_specialOffer
                      ? const SizedBox.shrink()
                      : Padding(
                          key: const ValueKey('offer-fields'),
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(children: [
                            TextFormField(controller: _salePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر العرض'), validator: _salePriceValidator),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(onPressed: _submitting ? null : _pickOfferEnd, icon: const Icon(Icons.event_outlined), label: Text(_saleEndsAt == null ? 'اختر تاريخ انتهاء العرض' : 'ينتهي ${MaterialLocalizations.of(context).formatMediumDate(_saleEndsAt!)}')),
                          ]),
                        ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'حالة المنتج'),
            items: [
              const DropdownMenuItem(value: 'draft', child: Text('مسودة')),
              if (widget.canPublish) const DropdownMenuItem(value: 'active', child: Text('منشور')),
              if (widget.isEditing) const DropdownMenuItem(value: 'hidden', child: Text('مخفي')),
            ],
            onChanged: _submitting ? null : (value) => setState(() => _status = value ?? _status),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: _submitting ? null : _pickImage, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(_image == null ? 'اختيار صورة المنتج' : 'تغيير صورة المنتج')),
          const SizedBox(height: 12),
          _imagePreview(),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _submitting ? null : _submit, icon: _submitting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(widget.isEditing ? 'حفظ التعديلات' : _status == 'active' ? 'حفظ ونشر المنتج' : 'حفظ كمسودة')),
          if (widget.isEditing) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _submitting ? null : _archive, icon: const Icon(Icons.archive_outlined), label: const Text('أرشفة المنتج')),
          ],
        ],
      ),
    ),
  );

  Widget _imagePreview() {
    if (_preview != null) {
      return FutureBuilder<Uint8List>(
        future: _preview,
        builder: (context, snapshot) => _previewBox(snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover) : const CircularProgressIndicator()),
      );
    }
    final currentMedia = widget.product?.mediaPublicId;
    if (currentMedia == null) return const SizedBox.shrink();
    return _previewBox(CachedMediaImage(mediaPublicId: currentMedia, errorIcon: Icons.broken_image_outlined));
  }

  Widget _previewBox(Widget child) => ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(height: 170, child: ColoredBox(color: const Color(0xFFF0F2F4), child: Center(child: child))));

  String? _priceValidator(String? value) {
    final parsed = num.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? 'أدخل سعراً صحيحاً.' : null;
  }

  String? _salePriceValidator(String? value) {
    final parsed = num.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? 'أدخل سعراً مخفضاً صحيحاً.' : null;
  }

  String? _stockValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? 'أدخل كمية صحيحة غير سالبة.' : null;
  }

  String? _positiveIntegerValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 1 ? 'أدخل رقماً موجباً.' : null;
  }

  String? _optionalPositiveIntegerValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _positiveIntegerValidator(value);
  }

  String? _skuValidator(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty || RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(text) ? null : 'استخدم حروفاً وأرقاماً و - _ . فقط.';
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Catalog, attribute and geographical hierarchy tools for marketplace admins.
/// Each status change calls the same validated server endpoints as the web app.
final class AdminMarketplaceSettingsPage extends StatefulWidget {
  const AdminMarketplaceSettingsPage({super.key});

  @override
  State<AdminMarketplaceSettingsPage> createState() =>
      _AdminMarketplaceSettingsPageState();
}

final class _AdminMarketplaceSettingsPageState
    extends State<AdminMarketplaceSettingsPage> {
  late Future<List<Map<String, dynamic>>> _categories;
  late Future<List<Map<String, dynamic>>> _countries;
  late Future<List<Map<String, dynamic>>> _transactions;
  String? _selectedCategory;
  String? _selectedCountry;
  String? _selectedCity;
  String _countrySearch = '';
  String _citySearch = '';
  String _districtSearch = '';
  String _transactionSearch = '';
  String _transactionStatus = '';
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      _reload();
    }
  }

  void _reload() => setState(() {
    final controller = AppScope.of(context);
    _categories = controller.loadAdminMarketplaceCategories();
    _countries = controller.loadAdminMarketplaceCountries();
    _transactions = controller.loadAdminMarketplaceTransactions();
  });

  Future<void> _save({
    required String type,
    String? publicId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final input = Map<String, dynamic>.from(body);
      final image = input.remove('_category_image');
      final optionText = (input.remove('_select_options') as String? ?? '');
      if (image is XFile) {
        input['image_media_id'] = await AppScope.of(context).uploadAdminPublicMedia(image);
      }
      final options = optionText
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (type == 'attribute' && publicId == null && options.isNotEmpty) {
        await AppScope.of(context).createAdminMarketplaceAttributeWithOptions(
          body: input,
          options: options,
        );
      } else {
        await AppScope.of(
          context,
        ).saveAdminMarketplaceEntity(type: type, publicId: publicId, body: input);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ التغيير بنجاح.')));
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deleteLocation(String type, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف آمن'),
        content: const Text(
          'سيمنع الخادم الحذف إن كان الموقع مستخدماً. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await AppScope.of(context)
          .deleteAdminMarketplaceLocation(type: type, publicId: id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حذف الموقع بأمان.')));
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<Map<String, dynamic>?> _entityDialog({
    required String title,
    required String type,
    Map<String, dynamic>? initial,
    List<Map<String, dynamic>> countries = const [],
    List<Map<String, dynamic>> cities = const [],
  }) async {
    final name = TextEditingController(
      text: initial?['name'] as String? ?? initial?['label'] as String? ?? '',
    );
    final code = TextEditingController(
      text: initial?['country_code'] as String? ?? '',
    );
    final order = TextEditingController(text: '${initial?['sort_order'] ?? 0}');
    final options = TextEditingController();
    XFile? categoryImage;
    var active = initial?['is_active'] as bool? ?? true;
    var required = initial?['is_required'] as bool? ?? false;
    var fieldType = initial?['field_type'] as String? ?? 'text';
    String? parentId = type == 'city'
        ? (initial?['country_public_id'] as String? ?? _selectedCountry)
        : type == 'district'
        ? (initial?['city_public_id'] as String? ?? _selectedCity)
        : null;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (type == 'country') ...[
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'رمز الدولة (مثال SY)',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: type == 'attribute' ? 'اسم السمة' : 'الاسم',
                  ),
                ),
                if (type == 'category') ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final image = await ImageUploadPolicy.pick(ImageSource.gallery);
                      if (image != null) setModalState(() => categoryImage = image);
                    },
                    icon: Icon(categoryImage == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline_rounded),
                    label: Text(categoryImage == null ? 'إرفاق صورة القسم (اختياري)' : 'تم اختيار صورة القسم'),
                  ),
                ],
                if (type == 'attribute') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: fieldType,
                    decoration: const InputDecoration(labelText: 'نوع السمة'),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('نص')),
                      DropdownMenuItem(value: 'number', child: Text('رقم')),
                      DropdownMenuItem(value: 'select', child: Text('قائمة')),
                      DropdownMenuItem(
                        value: 'boolean',
                        child: Text('نعم / لا'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => fieldType = value ?? fieldType),
                  ),
                  if (fieldType == 'select') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: options,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'خيارات القائمة',
                        hintText: 'مثال: جديد، مستعمل، شبه جديد',
                        helperText: 'تفصل الخيارات بفاصلة. تضاف الخيارات عند إنشاء السمة.',
                      ),
                    ),
                  ],
                ],
                if (type == 'city')
                  DropdownButtonFormField<String>(
                    initialValue: parentId,
                    decoration: const InputDecoration(labelText: 'الدولة'),
                    items: countries
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['public_id'] as String?,
                            child: Text(item['name'] as String? ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setModalState(() => parentId = value),
                  ),
                if (type == 'district')
                  DropdownButtonFormField<String>(
                    initialValue: parentId,
                    decoration: const InputDecoration(labelText: 'المدينة'),
                    items: cities
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['public_id'] as String?,
                            child: Text(item['name'] as String? ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setModalState(() => parentId = value),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ترتيب العرض'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (value) => setModalState(() => active = value),
                  title: const Text('مفعّل'),
                ),
                if (type == 'attribute')
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: required,
                    onChanged: (value) => setModalState(() => required = value),
                    title: const Text('إلزامية في الإعلان'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().length < 2 ||
                    ((type == 'city' || type == 'district') &&
                        parentId == null) ||
                    (type == 'country' && code.text.trim().length != 2)) {
                  return;
                }
                Navigator.pop(context, {
                  if (type == 'country') 'code': code.text.trim(),
                  if (type == 'attribute') 'category_id': _selectedCategory,
                  if (type == 'attribute') 'field_type': fieldType,
                  if (type == 'attribute') 'is_required': required,
                  if (type == 'attribute' && fieldType == 'select')
                    '_select_options': options.text.trim(),
                  if (type == 'category' && categoryImage != null)
                    '_category_image': categoryImage,
                  if (type == 'city') 'country_id': parentId,
                  if (type == 'district') 'city_id': parentId,
                  'name': name.text.trim(),
                  if (type == 'attribute') 'label': name.text.trim(),
                  'sort_order': int.tryParse(order.text.trim()) ?? 0,
                  'is_active': active,
                });
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    code.dispose();
    order.dispose();
    options.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الحراج'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
        bottom: adminTabbedBottom(
          context,
          'marketplace',
          const TabBar(
            isScrollable: true,
            tabs: [
            Tab(text: 'الأقسام'),
            Tab(text: 'السمات'),
            Tab(text: 'المواقع'),
            Tab(text: 'الصفقات'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        children: [_categoriesTab(), _attributesTab(), _locationsTab(), _transactionsTab()],
      ),
    ),
  );

  Widget _categoriesTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _categories,
    builder: (context, snapshot) => _AsyncItems(
      snapshot: snapshot,
      empty: 'لا توجد أقسام حراج.',
      onAdd: () async {
        final body = await _entityDialog(
          title: 'قسم حراج جديد',
          type: 'category',
        );
        if (body != null) _save(type: 'category', body: body);
      },
      itemBuilder: (item) => ListTile(
        leading: Icon(
          item['is_active'] == true
              ? Icons.category_outlined
              : Icons.category_outlined,
        ),
        title: Text(item['name'] as String? ?? ''),
        subtitle: Text(
          '${item['is_active'] == true ? 'مفعّل' : 'موقوف'} · ترتيب ${item['sort_order'] ?? 0}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final body = await _entityDialog(
              title: 'تعديل القسم',
              type: 'category',
              initial: item,
            );
            if (body != null) {
              _save(
                type: 'category',
                publicId: item['public_id'] as String?,
                body: body,
              );
            }
          },
        ),
      ),
    ),
  );

  Widget _attributesTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _categories,
    builder: (context, categorySnapshot) {
      final categories =
          categorySnapshot.data ?? const <Map<String, dynamic>>[];
      if (_selectedCategory == null && categories.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => setState(
            () => _selectedCategory = categories.first['public_id'] as String?,
          ),
        );
      }
      if (categories.isEmpty) {
        return const Center(child: Text('أضف قسماً أولاً.'));
      }
      final selected = _selectedCategory;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: categories
                  .map(
                    (item) => DropdownMenuItem(
                      value: item['public_id'] as String?,
                      child: Text(item['name'] as String? ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
          ),
          Expanded(
            child: selected == null
                ? const SizedBox()
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: AppScope.of(context)
                        .loadAdminMarketplaceAttributes(selected),
                    builder: (context, snapshot) => _AsyncItems(
                      snapshot: snapshot,
                      empty: 'لا توجد سمات لهذا القسم.',
                      onAdd: () async {
                        final body = await _entityDialog(
                          title: 'سمة جديدة',
                          type: 'attribute',
                        );
                        if (body != null) _save(type: 'attribute', body: body);
                      },
                      itemBuilder: (item) => ListTile(
                        title: Text(item['label'] as String? ?? ''),
                        subtitle: Text(
                          '${item['field_type'] ?? ''} · ${item['is_required'] == true ? 'إلزامية' : 'اختيارية'} · ${item['is_active'] == true ? 'مفعّلة' : 'موقوفة'}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final body = await _entityDialog(
                              title: 'تعديل السمة',
                              type: 'attribute',
                              initial: item,
                            );
                            if (body != null) {
                              _save(
                                type: 'attribute',
                                publicId: item['public_id'] as String?,
                                body: body,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );

  Widget _transactionsTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _transactions,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل صفقات الحراج.'));
      final items = snapshot.data ?? const <Map<String, dynamic>>[];
      final term = _transactionSearch.trim().toLowerCase();
      final visible = items.where((item) => (_transactionStatus.isEmpty || item['transaction_status'] == _transactionStatus) && (term.isEmpty || [item['public_id'], item['listing_title'], item['buyer_name'], item['seller_name'], item['transaction_status']].any((value) => '$value'.toLowerCase().contains(term)))).toList(growable: false);
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Row(children: [
          Expanded(child: TextField(onChanged: (value) => setState(() => _transactionSearch = value), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'الإعلان أو الطرف أو معرف الصفقة'))),
          const SizedBox(width: 8),
          SizedBox(width: 145, child: DropdownButtonFormField<String>(value: _transactionStatus, isExpanded: true, decoration: const InputDecoration(labelText: 'الحالة'), items: const [DropdownMenuItem(value: '', child: Text('الكل')), DropdownMenuItem(value: 'reserved', child: Text('محجوزة')), DropdownMenuItem(value: 'disputed', child: Text('نزاع')), DropdownMenuItem(value: 'completed', child: Text('مكتملة')), DropdownMenuItem(value: 'cancelled', child: Text('ملغاة'))], onChanged: (value) => setState(() => _transactionStatus = value ?? ''))),
        ])),
        Expanded(child: visible.isEmpty ? Center(child: Text(items.isEmpty ? 'لا توجد صفقات حراج مسجلة.' : 'لا توجد صفقات مطابقة.')) : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = visible[index];
          final id = item['public_id'] as String? ?? '';
          final image = item['listing_primary_media_public_id'] as String?;
          return Card(
            child: ListTile(
              leading: image == null
                  ? const CircleAvatar(child: Icon(Icons.handshake_outlined))
                  : ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(width: 44, height: 44, child: CachedMediaImage(mediaPublicId: image))),
              title: Text(item['listing_title'] as String? ?? 'صفقة حراج', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${item['buyer_name'] ?? 'مشتري'} ← ${item['seller_name'] ?? 'بائع'}\n${item['agreed_amount'] ?? 0} ${item['currency_code'] ?? ''} · ${item['transaction_status'] ?? '—'}${item['delivery_task_status'] != null ? ' · توصيل: ${item['delivery_task_status']}' : ''}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: id.isEmpty ? null : () => _showMarketplaceTransaction(id),
            ),
          );
        },
      )),
      ]);
    },
  );

  Future<void> _showMarketplaceTransaction(String id) async {
    try {
      final data = await AppScope.of(context).loadAdminMarketplaceTransactionDetail(id);
      if (!mounted) return;
      final transaction = Map<String, dynamic>.from(data['transaction'] as Map? ?? const {});
      final delivery = data['delivery'] is Map ? Map<String, dynamic>.from(data['delivery'] as Map) : null;
      final dispute = data['dispute'] is Map ? Map<String, dynamic>.from(data['dispute'] as Map) : null;
      final conversation = data['conversation'] is Map ? Map<String, dynamic>.from(data['conversation'] as Map) : null;
      final messages = (data['messages'] as List? ?? const []).whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList(growable: false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .76,
          maxChildSize: .94,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
            children: [
              Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 16),
              Text('تفاصيل صفقة الحراج', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              _marketplaceDetailBlock('الصفقة والإعلان', transaction),
              if (delivery != null) _marketplaceDetailBlock('التوصيل المرتبط', delivery),
              if (dispute != null) _marketplaceDetailBlock('النزاع المرتبط', dispute),
              if (conversation != null) _marketplaceDetailBlock('المحادثة المرتبطة', conversation),
              if (messages.isNotEmpty) ...[
                const SizedBox(height: 16), const Text('سجل المحادثة', style: TextStyle(fontWeight: FontWeight.w900)),
                ...messages.map((message) => Card(child: ListTile(title: Text(message['sender_name'] as String? ?? 'مستخدم'), subtitle: Text('${message['body'] ?? ''}\n${message['created_at'] ?? ''}')))),
              ],
            ],
          ),
        )),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Widget _locationsTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _countries,
    builder: (context, countrySnapshot) {
      final countries = countrySnapshot.data ?? const <Map<String, dynamic>>[];
      if (_selectedCountry == null && countries.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => setState(
            () => _selectedCountry = countries.first['public_id'] as String?,
          ),
        );
      }
      return Column(
        children: [
          Expanded(
            child: _AsyncItems(
              snapshot: countrySnapshot,
              empty: 'لا توجد دول مضافة.',
              onAdd: () async {
                final body = await _entityDialog(
                  title: 'إضافة دولة',
                  type: 'country',
                );
                if (body != null) _save(type: 'country', body: body);
              },
              header: 'الدول',
              searchQuery: _countrySearch,
              onSearchChanged: (value) =>
                  setState(() => _countrySearch = value),
              itemBuilder: (item) =>
                  _locationTile(item, type: 'country', countries: countries),
            ),
          ),
          const Divider(height: 1),
          if (_selectedCountry != null)
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: AppScope.of(context)
                    .loadAdminMarketplaceCities(_selectedCountry!),
                builder: (context, citySnapshot) {
                  final cities =
                      citySnapshot.data ?? const <Map<String, dynamic>>[];
                  if (_selectedCity == null && cities.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => setState(
                        () => _selectedCity =
                            cities.first['public_id'] as String?,
                      ),
                    );
                  }
                  return _AsyncItems(
                    snapshot: citySnapshot,
                    empty: 'لا توجد مدن لهذه الدولة.',
                    header: 'مدن الدولة المحددة',
                    searchQuery: _citySearch,
                    onSearchChanged: (value) =>
                        setState(() => _citySearch = value),
                    onAdd: () async {
                      final body = await _entityDialog(
                        title: 'إضافة مدينة',
                        type: 'city',
                        countries: countries,
                      );
                      if (body != null) _save(type: 'city', body: body);
                    },
                    itemBuilder: (item) => _locationTile(
                      item,
                      type: 'city',
                      countries: countries,
                      cities: cities,
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          if (_selectedCity != null)
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: AppScope.of(context)
                    .loadAdminMarketplaceDistricts(_selectedCity!),
                builder: (context, snapshot) => _AsyncItems(
                  snapshot: snapshot,
                  empty: 'لا توجد مناطق لهذه المدينة.',
                  header: 'مناطق المدينة المحددة',
                  searchQuery: _districtSearch,
                  onSearchChanged: (value) =>
                      setState(() => _districtSearch = value),
                  onAdd: () async {
                    final body = await _entityDialog(
                      title: 'إضافة منطقة',
                      type: 'district',
                    );
                    if (body != null) _save(type: 'district', body: body);
                  },
                  itemBuilder: (item) => _locationTile(item, type: 'district'),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _locationTile(
    Map<String, dynamic> item, {
    required String type,
    List<Map<String, dynamic>> countries = const [],
    List<Map<String, dynamic>> cities = const [],
  }) => ListTile(
    selected:
        (type == 'country' && item['public_id'] == _selectedCountry) ||
        (type == 'city' && item['public_id'] == _selectedCity),
    onTap: type == 'country'
        ? () => setState(() {
            _selectedCountry = item['public_id'] as String?;
            _selectedCity = null;
          })
        : type == 'city'
        ? () => setState(() => _selectedCity = item['public_id'] as String?)
        : null,
    title: Text(item['name'] as String? ?? ''),
    subtitle: Text(
      '${item['country_code'] ?? ''} ${item['is_active'] == true ? '· مفعّل' : '· موقوف'}',
    ),
    trailing: Wrap(
      spacing: 0,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final body = await _entityDialog(
              title: 'تعديل',
              type: type,
              initial: item,
              countries: countries,
              cities: cities,
            );
            if (body != null) {
              _save(
                type: type,
                publicId: item['public_id'] as String?,
                body: body,
              );
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteLocation(type, item['public_id'] as String),
        ),
      ],
    ),
  );
}

Widget _marketplaceDetailBlock(String title, Map<String, dynamic> values) {
  const labels = {
    'public_id': 'المعرف', 'listing_public_id': 'معرف الإعلان', 'listing_title': 'الإعلان', 'listing_description': 'وصف الإعلان', 'listing_status': 'حالة الإعلان',
    'buyer_name': 'المشتري', 'buyer_phone': 'هاتف المشتري', 'seller_name': 'البائع', 'seller_phone': 'هاتف البائع', 'agreed_amount': 'المبلغ المتفق عليه',
    'currency_code': 'العملة', 'transaction_status': 'حالة الصفقة', 'offer_public_id': 'معرف العرض', 'offer_amount': 'قيمة العرض', 'offer_status': 'حالة العرض', 'offer_expires_at': 'انتهاء العرض',
    'task_public_id': 'معرف المهمة', 'task_status': 'حالة المهمة', 'request_status': 'حالة طلب التوصيل', 'fee_amount': 'رسم التوصيل', 'distance_km': 'المسافة كم', 'courier_name': 'عامل التوصيل',
    'reason_code': 'سبب النزاع', 'details': 'التفاصيل', 'resolution_note': 'قرار الإدارة', 'status': 'الحالة', 'opened_at': 'تاريخ الفتح', 'resolved_at': 'تاريخ الحسم', 'created_at': 'تاريخ الإنشاء', 'updated_at': 'آخر تحديث',
  };
  final rows = values.entries.where((entry) => entry.value != null && entry.value is! Map && entry.value is! List && '${entry.value}'.trim().isNotEmpty).toList(growable: false);
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 16), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
    ...rows.map((entry) => Card(child: ListTile(title: Text(labels[entry.key] ?? entry.key), subtitle: SelectableText('${entry.value}')))),
  ]);
}

final class _AsyncItems extends StatelessWidget {
  const _AsyncItems({
    required this.snapshot,
    required this.empty,
    required this.onAdd,
    required this.itemBuilder,
    this.header,
    this.searchQuery,
    this.onSearchChanged,
  });
  final AsyncSnapshot<List<Map<String, dynamic>>> snapshot;
  final String empty;
  final VoidCallback onAdd;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  final String? header;
  final String? searchQuery;
  final ValueChanged<String>? onSearchChanged;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) return Center(child: Text('تعذر تحميل البيانات.'));
    final items = snapshot.data ?? const <Map<String, dynamic>>[];
    final query = searchQuery?.trim().toLowerCase() ?? '';
    final visibleItems = query.isEmpty
        ? items
        : items
              .where(
                (item) => '${item['name'] ?? ''} ${item['country_code'] ?? ''}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 10, 0),
          child: Row(
            children: [
              if (header != null)
                Expanded(
                  child: Text(
                    header!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: 'إضافة',
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        if (onSearchChanged != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'بحث بالاسم أو الرمز',
                isDense: true,
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(empty))
              : visibleItems.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: visibleItems.length,
                  itemBuilder: (context, index) =>
                      itemBuilder(visibleItems[index]),
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                ),
        ),
      ],
    );
  }
}

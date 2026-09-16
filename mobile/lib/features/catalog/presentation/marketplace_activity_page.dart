import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'catalog_detail_pages.dart';
import 'marketplace_delivery_request_page.dart';
import 'marketplace_listing_editor_page.dart';
import 'marketplace_listing_update_page.dart';
import 'marketplace_promotion_page.dart';

/// Personal marketplace workspaces exposed as visible tabs, matching the web
/// actions rather than hiding them in an app-bar overflow menu.
final class MarketplaceActivityPage extends StatelessWidget {
  const MarketplaceActivityPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        initialIndex: initialIndex.clamp(0, 3).toInt(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('مساحة الحراج'),
            actions: [
              IconButton(
                tooltip: 'إضافة إعلان',
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MarketplaceListingEditorPage(),
                  ),
                ),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'إعلاناتي'),
                Tab(text: 'المفضلة'),
                Tab(text: 'المحادثات'),
                Tab(text: 'صفقاتي'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _MarketplaceItemsTab(kind: _MarketplaceItemsKind.mine),
              _MarketplaceItemsTab(kind: _MarketplaceItemsKind.favorites),
              _MarketplaceItemsTab(kind: _MarketplaceItemsKind.conversations),
              _MarketplaceItemsTab(kind: _MarketplaceItemsKind.transactions),
            ],
          ),
        ),
      );
}

enum _MarketplaceItemsKind { mine, favorites, conversations, transactions }

final class _MarketplaceItemsTab extends StatefulWidget {
  const _MarketplaceItemsTab({required this.kind});
  final _MarketplaceItemsKind kind;

  @override
  State<_MarketplaceItemsTab> createState() => _MarketplaceItemsTabState();
}

final class _MarketplaceItemsTabState extends State<_MarketplaceItemsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final controller = AppScope.of(context);
    return switch (widget.kind) {
      _MarketplaceItemsKind.mine => controller.loadMyMarketplaceListings(),
      _MarketplaceItemsKind.favorites => controller.loadMarketplaceFavorites(),
      _MarketplaceItemsKind.conversations => controller.loadMarketplaceConversations(),
      _MarketplaceItemsKind.transactions => controller.loadMarketplaceTransactions(),
    };
  }

  Future<void> _transactionAction(String id, String action) async {
    try {
      await AppScope.of(context).updateMarketplaceTransaction(
        transactionId: id,
        action: action,
      );
      if (mounted) setState(() => _future = _load());
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _confirmDelivery(String taskId) async {
    try {
      await AppScope.of(context).confirmMarketplaceDelivery(taskId);
      if (mounted) setState(() => _future = _load());
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openDispute(String transactionId) async {
    final reason = TextEditingController();
    final details = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فتح نزاع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب النزاع *')),
            const SizedBox(height: 9),
            TextField(controller: details, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'تفاصيل إضافية')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('فتح النزاع')),
        ],
      ),
    );
    final reasonText = reason.text.trim();
    final detailsText = details.text.trim();
    reason.dispose();
    details.dispose();
    if (confirmed != true || reasonText.length < 2 || !mounted) return;
    try {
      await AppScope.of(context).openMarketplaceDispute(
        transactionId: transactionId,
        reasonCode: reasonText,
        details: detailsText,
      );
      if (mounted) setState(() => _future = _load());
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _ActivityEmpty(
              icon: Icons.cloud_off_rounded,
              title: error is ApiException ? error.message : 'تعذر تحميل هذه البيانات.',
              action: () => setState(() => _future = _load()),
              actionLabel: 'إعادة المحاولة',
            );
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return _ActivityEmpty(
              icon: _emptyIcon,
              title: _emptyText,
              action: () => setState(() => _future = _load()),
              actionLabel: 'تحديث',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _item(context, items[index]),
            ),
          );
        },
      );

  IconData get _emptyIcon => switch (widget.kind) {
        _MarketplaceItemsKind.mine => Icons.add_box_outlined,
        _MarketplaceItemsKind.favorites => Icons.favorite_border_rounded,
        _MarketplaceItemsKind.conversations => Icons.forum_outlined,
        _MarketplaceItemsKind.transactions => Icons.handshake_outlined,
      };

  String get _emptyText => switch (widget.kind) {
        _MarketplaceItemsKind.mine => 'لا توجد إعلانات خاصة بك حالياً.',
        _MarketplaceItemsKind.favorites => 'لا توجد إعلانات في المفضلة.',
        _MarketplaceItemsKind.conversations => 'لا توجد محادثات حراج حالياً.',
        _MarketplaceItemsKind.transactions => 'لا توجد صفقات حراج حالياً.',
      };

  Widget _item(BuildContext context, Map<String, dynamic> item) {
    if (widget.kind == _MarketplaceItemsKind.conversations) {
      final id = item['public_id'] as String? ?? '';
      final unreadCount = (item['unread_count'] as num?)?.toInt() ?? 0;
      return _ActivityTile(
        icon: Icons.forum_outlined,
        title: item['title'] as String? ?? 'محادثة حراج',
        subtitle: 'مراسلة بخصوص الإعلان',
        trailing: unreadCount > 0
            ? Badge(
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.forum_outlined),
              )
            : null,
        onTap: id.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MarketplaceConversationPage(
                      conversationId: id,
                      title: item['title'] as String? ?? 'محادثة حراج',
                    ),
                  ),
                ),
      );
    }
    if (widget.kind == _MarketplaceItemsKind.transactions) {
      final id = item['public_id'] as String? ?? '';
      final status = item['transaction_status'] as String? ?? 'reserved';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صفقة حراج', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('${item['agreed_amount'] ?? 0} ${item['currency_code'] ?? ''} · ${_statusLabel(status)}'),
              if (status == 'reserved' && id.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _transactionAction(id, 'complete'),
                      child: const Text('إتمام الصفقة'),
                    ),
                    OutlinedButton(
                      onPressed: () => _transactionAction(id, 'cancel'),
                      child: const Text('إلغاء'),
                    ),
                    if (item['can_confirm_delivery'] == true && item['delivery_task_status'] == 'delivered' && item['delivery_task_public_id'] is String)
                      FilledButton.tonal(
                        onPressed: () => _confirmDelivery(item['delivery_task_public_id'] as String),
                        child: const Text('تأكيد الاستلام'),
                      ),
                    TextButton(
                      onPressed: () async {
                        final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => MarketplaceDeliveryRequestPage(transactionId: id),
                          ),
                        );
                        if (created == true && mounted) setState(() => _future = _load());
                      },
                      child: const Text('طلب توصيل'),
                    ),
                    TextButton(
                      onPressed: () => _openDispute(id),
                      child: const Text('فتح نزاع'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
    final title = item['title'] as String? ?? 'إعلان حراج';
    final listingId = item['public_id'] as String? ?? '';
    if (widget.kind == _MarketplaceItemsKind.mine) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text('${item['listing_status'] ?? 'مسودة'} · ${item['price_amount'] ?? 'السعر عند التواصل'} ${item['currency_code'] ?? ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item['listing_status'] == 'active')
                IconButton(
                  tooltip: 'ترويج الإعلان',
                  icon: const Icon(Icons.campaign_outlined),
                  onPressed: listingId.isEmpty
                      ? null
                      : () async {
                          final completed = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => MarketplacePromotionPage(
                                listingId: listingId,
                                currencyCode: item['currency_code'] as String? ?? 'USD',
                              ),
                            ),
                          );
                          if (completed == true && mounted) setState(() => _future = _load());
                        },
                ),
              IconButton(
                tooltip: 'تعديل الإعلان',
                icon: const Icon(Icons.edit_outlined),
                onPressed: listingId.isEmpty
                    ? null
                    : () async {
                        final updated = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => MarketplaceListingUpdatePage(listingId: listingId, title: title),
                          ),
                        );
                        if (updated == true && mounted) setState(() => _future = _load());
                      },
              ),
            ],
          ),
        ),
      );
    }
    return _ActivityTile(
      icon: Icons.favorite_rounded,
      title: title,
      subtitle: '${item['listing_status'] ?? item['city'] ?? 'إعلان حراج'}',
      onTap: listingId.isEmpty
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ListingDetailsPage(listingId: listingId, title: title),
                ),
              ),
    );
  }

  String _statusLabel(String value) => switch (value) {
        'reserved' => 'محجوزة',
        'completed' => 'مكتملة',
        'cancelled' => 'ملغاة',
        'disputed' => 'قيد النزاع',
        _ => value,
      };
}

final class MarketplaceConversationPage extends StatefulWidget {
  const MarketplaceConversationPage({
    super.key,
    required this.conversationId,
    required this.title,
  });
  final String conversationId;
  final String title;

  @override
  State<MarketplaceConversationPage> createState() => _MarketplaceConversationPageState();
}

final class _MarketplaceConversationPageState extends State<MarketplaceConversationPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _message = TextEditingController();
  Timer? _poller;
  bool _loaded = false;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _future = AppScope.of(context).loadConversationMessages(widget.conversationId);
    // Keep an already-open thread current even when foreground push is not
    // available. The server remains authoritative for the message list.
    _poller = Timer.periodic(const Duration(seconds: 15), (_) => _reload());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _message.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = AppScope.of(context).loadConversationMessages(widget.conversationId));
  }

  Future<void> _submitOffer() async {
    final amount = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تقديم عرض شراء'),
        content: TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'قيمة العرض'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('إرسال العرض')),
        ],
      ),
    );
    final value = amount.text.trim();
    amount.dispose();
    if (submitted != true || value.isEmpty || !mounted) return;
    try {
      await AppScope.of(context).sendMarketplaceOffer(
        conversationId: widget.conversationId,
        amount: value,
      );
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _decideOffer(String offerId, String decision) async {
    try {
      await AppScope.of(context).decideMarketplaceOffer(offerId: offerId, decision: decision);
      if (mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await AppScope.of(context).sendConversationMessage(
        conversationId: widget.conversationId,
        body: text,
      );
      if (!mounted) return;
      _message.clear();
      setState(() => _future = AppScope.of(context).loadConversationMessages(widget.conversationId));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return _ActivityEmpty(icon: Icons.cloud_off_rounded, title: 'تعذر تحميل المحادثة.', action: () => setState(() => _future = AppScope.of(context).loadConversationMessages(widget.conversationId)), actionLabel: 'إعادة المحاولة');
                  final messages = snapshot.data ?? const <Map<String, dynamic>>[];
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = messages[index];
                      final mine = item['is_mine'] == true;
                      return Align(
                        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['body'] as String? ?? ''),
                              if (item['offer'] is Map) ...[
                                const SizedBox(height: 6),
                                _OfferMessageActions(
                                  offer: Map<String, dynamic>.from(item['offer'] as Map),
                                  isMine: mine,
                                  onDecision: _decideOffer,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _message,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'اكتب رسالتك…'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'تقديم عرض شراء',
                      onPressed: _sending ? null : _submitOffer,
                      icon: const Icon(Icons.local_offer_outlined),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: 'إرسال',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

final class _OfferMessageActions extends StatelessWidget {
  const _OfferMessageActions({
    required this.offer,
    required this.isMine,
    required this.onDecision,
  });

  final Map<String, dynamic> offer;
  final bool isMine;
  final Future<void> Function(String offerId, String decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final status = offer['offer_status'] as String? ?? 'pending';
    final offerId = offer['public_id'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${offer['amount'] ?? 0} ${offer['currency_code'] ?? ''} · ${_status(status)}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        if (!isMine && status == 'pending' && offerId.isNotEmpty) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            children: [
              FilledButton.tonal(
                onPressed: () => onDecision(offerId, 'accept'),
                child: const Text('قبول العرض'),
              ),
              OutlinedButton(
                onPressed: () => onDecision(offerId, 'reject'),
                child: const Text('رفض'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _status(String value) => switch (value) {
        'pending' => 'بانتظار قرار البائع',
        'accepted' => 'تم القبول',
        'rejected' => 'مرفوض',
        'expired' => 'منتهي',
        _ => value,
      };
}

final class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.icon, required this.title, required this.subtitle, this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      );
}

final class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({required this.icon, required this.title, required this.action, required this.actionLabel});
  final IconData icon;
  final String title;
  final VoidCallback action;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: Text(actionLabel)),
            ],
          ),
        ),
      );
}

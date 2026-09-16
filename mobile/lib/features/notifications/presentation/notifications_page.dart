import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'notification_target_router.dart';
import '../data/notification_repository.dart';
import '../data/firebase_push_service.dart';
import 'notification_preferences_page.dart';

final class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

final class _NotificationsPageState extends State<NotificationsPage> {
  late Future<NotificationFeed> _future;
  int? _notificationRevision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (_notificationRevision != controller.notificationRevision) {
      _notificationRevision = controller.notificationRevision;
      _future = controller.loadNotifications();
    }
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadNotifications());

  Future<void> _markAllRead() async {
    try {
      await AppScope.of(context).markAllNotificationsRead();
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      await AppScope.of(context).markNotificationRead(notification.publicId);
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _open(AppNotification notification) async {
    await _markRead(notification);
    if (!mounted) return;
    final opened = await openNotificationTarget(
      context,
      entityType: notification.entityType,
      entityPublicId: notification.entityPublicId,
      category: notification.category,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد وجهة مباشرة لهذا التنبيه؛ يمكنك مراجعة تفاصيله هنا.')));
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الإشعارات'),
      actions: [
        IconButton(tooltip: 'إعدادات الإشعارات', icon: const Icon(Icons.tune_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationPreferencesPage()))),
        TextButton(onPressed: _markAllRead, child: const Text('تعليم الكل')),
      ],
    ),
    body: Column(
      children: [
        _pushStatus(context),
        Expanded(child: FutureBuilder<NotificationFeed>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل الإشعارات.';
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة'))])));
        }
        final feed = snapshot.data ?? const NotificationFeed(items: [], unreadCount: 0);
        if (feed.items.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_none_rounded, size: 48), SizedBox(height: 12), Text('لا توجد إشعارات جديدة')])));
        return RefreshIndicator(
          onRefresh: () async { _reload(); },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: feed.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = feed.items[index];
              return Card(
                color: item.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withOpacity(.42),
                child: ListTile(
                  onTap: () => _open(item),
                  leading: CircleAvatar(
                    backgroundColor: item.isRead ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(_icon(item.category), color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.body)),
                  trailing: item.isRead ? null : const Icon(Icons.circle, size: 10),
                ),
              );
            },
          ),
        );
      },
    )),
      ],
    ),
  );

  Widget _pushStatus(BuildContext context) {
    final controller = AppScope.of(context);
    final permission = controller.pushPermissionState;
    final registration = controller.pushDeviceRegistrationState;
    final (icon, label, detail, color) = switch ((permission, registration)) {
      (PushPermissionState.granted, PushDeviceRegistrationState.registered) => (Icons.check_circle_outline_rounded, 'إشعارات الجهاز مفعّلة', 'تم تسجيل هذا الجهاز لاستقبال إشعارات تجارتي.', Theme.of(context).colorScheme.primary),
      (PushPermissionState.granted, PushDeviceRegistrationState.registering) => (Icons.sync_rounded, 'جارٍ تسجيل الجهاز', 'يتم ربط الجهاز بخدمة الإشعارات.', Theme.of(context).colorScheme.primary),
      (PushPermissionState.granted, PushDeviceRegistrationState.failed) => (Icons.cloud_off_outlined, 'تعذر تسجيل الجهاز', 'تحقق من الإنترنت ثم حدّث هذه الصفحة لإعادة المحاولة.', Theme.of(context).colorScheme.error),
      (PushPermissionState.denied, _) => (Icons.notifications_off_outlined, 'إذن الإشعارات موقوف', 'فعّله من إعدادات Android لتصلك التنبيهات الخارجية.', Theme.of(context).colorScheme.error),
      (PushPermissionState.unavailable, _) => (Icons.info_outline_rounded, 'إشعارات الجهاز غير متاحة', 'يبقى سجل الإشعارات داخل التطبيق متاحاً.', Theme.of(context).colorScheme.onSurfaceVariant),
      _ => (Icons.notifications_paused_outlined, 'إشعارات الجهاز بانتظار التفعيل', 'فعّل الإذن لتسجيل هذا الجهاز واستلام التنبيهات.', Theme.of(context).colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(detail),
        trailing: IconButton(tooltip: 'تحديث حالة الجهاز', icon: const Icon(Icons.refresh_rounded), onPressed: () async { await controller.refreshPushPermissionState(); if (mounted) setState(() {}); }),
      )),
    );
  }

  IconData _icon(String category) => switch (category) {
    'delivery' => Icons.local_shipping_outlined,
    'wallet' => Icons.account_balance_wallet_outlined,
    'support' => Icons.support_agent_rounded,
    _ => Icons.notifications_outlined,
  };
}

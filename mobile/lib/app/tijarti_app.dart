import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/notifications/presentation/notification_target_router.dart';
import '../features/notifications/data/firebase_push_service.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/home/presentation/home_shell.dart';
import 'app_controller.dart';
import 'app_scope.dart';
import 'app_theme.dart';

final class TijartiApp extends StatefulWidget {
  const TijartiApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<TijartiApp> createState() => _TijartiAppState();
}

final class _TijartiAppState extends State<TijartiApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<NotificationTarget>? _notificationTargetSubscription;
  final List<NotificationTarget> _pendingPushTargets = <NotificationTarget>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationTargetSubscription = widget.controller.notificationTargets.listen(
      _openPushTarget,
    );
    unawaited(widget.controller.bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTargetSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refreshNotificationBadge());
      unawaited(widget.controller.refreshPushPermissionState());
    }
  }

  void _openPushTarget(NotificationTarget target) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // Cold-start FCM taps can arrive before MaterialApp creates its navigator.
      _pendingPushTargets.add(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = List<NotificationTarget>.from(_pendingPushTargets);
        _pendingPushTargets.clear();
        for (final queuedTarget in pending) { _openPushTarget(queuedTarget); }
      });
      return;
    }
    final context = navigator.context;
    unawaited(openNotificationTarget(
      context,
      entityType: target.entityType,
      entityPublicId: target.entityPublicId,
      category: target.category,
    ).then((opened) {
      // Unknown types still land on the in-app feed rather than dropping the tap.
      if (!opened && context.mounted) {
        navigator.push(MaterialPageRoute<void>(builder: (_) => const NotificationsPage()));
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'تجارتي',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

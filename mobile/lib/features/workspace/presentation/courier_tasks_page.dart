import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../data/workspace_repository.dart';
import 'courier_proof_page.dart';
import 'courier_navigation_page.dart';

final class CourierTasksPage extends StatefulWidget {
  const CourierTasksPage({super.key});

  @override
  State<CourierTasksPage> createState() => _CourierTasksPageState();
}

final class _CourierTasksPageState extends State<CourierTasksPage> {
  late Future<CourierWorkspace> _future;
  bool _loaded = false;
  String? _workingTask;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadCourierWorkspace();
    }
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadCourierWorkspace());

  Future<void> _availability(bool available) async {
    try {
      await AppScope.of(context).setCourierAvailability(available);
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _handleTask(Map<String, dynamic> task) async {
    final taskId = task['public_id'] as String?;
    final status = task['task_status'] as String?;
    if (taskId == null || status == null) return;
    if (status == 'available') {
      await _accept(taskId, task['source_type'] as String? ?? 'store_order');
      return;
    }
    final action = _nextAction(status);
    if (action == null) return;
    XFile? proof;
    if (action.requiresProof) {
      proof = await Navigator.of(context).push<XFile>(
        MaterialPageRoute<XFile>(
          builder: (_) => CourierProofPage(
            title: action.title,
            description: action.code == 'picked_up'
                ? 'التقط صورة واضحة للطلب بعد استلامه من المتجر.'
                : 'التقط صورة إثبات التسليم وفق سياسة التوصيل.',
          ),
        ),
      );
      if (proof == null || !mounted) return;
    }
    setState(() => _workingTask = taskId);
    try {
      await AppScope.of(context).transitionCourierTask(
        taskId: taskId,
        action: action.code,
        sourceType: task['source_type'] as String? ?? 'store_order',
        proof: proof,
      );
      _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ${action.title}.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on FormatException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _workingTask = null);
    }
  }

  Future<void> _accept(String taskId, String sourceType) async {
    setState(() => _workingTask = taskId);
    try {
      await AppScope.of(context).acceptCourierTask(
        taskId,
        sourceType: sourceType,
      );
      _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول مهمة التوصيل.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _workingTask = null);
    }
  }

  _TaskAction? _nextAction(String status) => switch (status) {
    'accepted' => const _TaskAction(code: 'heading_to_pickup', title: 'بدء التوجه للاستلام'),
    'en_route_pickup' => const _TaskAction(code: 'picked_up', title: 'تأكيد استلام الطلب', requiresProof: true),
    'picked_up' => const _TaskAction(code: 'heading_to_delivery', title: 'بدء التوجه للعميل'),
    'en_route_delivery' => const _TaskAction(code: 'delivered', title: 'تأكيد التسليم', requiresProof: true),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مهام التوصيل')),
    body: FutureBuilder<CourierWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل المهام.';
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة'))])));
        }
        final workspace = snapshot.data!;
        final verified = workspace.profile['verification_status'] == 'verified';
        final available = workspace.profile['work_status'] == 'available';
        return RefreshIndicator(
          onRefresh: () async { _reload(); },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
            Card(
              child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(verified ? 'حساب التوصيل موثّق' : 'بانتظار توثيق حساب التوصيل', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                Text(verified ? 'فعّل التوفر لتظهر لك المهام القابلة للاستلام.' : 'سيصلك إشعار عند اعتماد حسابك من الإدارة.'),
                if (verified) SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: available, onChanged: _availability, title: const Text('متاح لاستلام المهام')),
              ])),
            ),
            const SizedBox(height: 20),
            Text('المهام', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (workspace.tasks.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Center(child: Text('لا توجد مهام متاحة حالياً.'))))
            else ...workspace.tasks.map((task) => _TaskCard(task: task, busy: _workingTask == task['public_id'], action: task['task_status'] == 'available' ? const _TaskAction(code: 'accept', title: 'قبول المهمة') : _nextAction(task['task_status'] as String? ?? ''), onAction: () => _handleTask(task), onMap: task['task_status'] == 'available' ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourierNavigationPage(task: task)))),),
          ]),
        );
      },
    ),
  );
}

final class _TaskAction {
  const _TaskAction({required this.code, required this.title, this.requiresProof = false});
  final String code;
  final String title;
  final bool requiresProof;
}

final class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.busy, required this.action, required this.onAction, this.onMap});
  final Map<String, dynamic> task;
  final bool busy;
  final _TaskAction? action;
  final VoidCallback onAction;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    final status = task['task_status'] as String? ?? 'available';
    final store = task['store'];
    final storeName = store is Map ? store['name'] as String? : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(status == 'available' ? Icons.local_shipping_outlined : Icons.route_rounded, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Expanded(child: Text(task['order_number'] as String? ?? 'مهمة توصيل', style: const TextStyle(fontWeight: FontWeight.w900))), Text(_statusText(status))]),
        if (storeName != null) Padding(padding: const EdgeInsets.only(top: 9), child: Text('الاستلام من: $storeName')),
        Padding(padding: const EdgeInsets.only(top: 5), child: Text('رسوم التوصيل: ${task['delivery_fee_amount'] ?? 0} ${task['currency_code'] ?? 'USD'}')),
        if (task['delivery_distance_km'] != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text('مسافة الطريق: ${task['delivery_distance_km']} كم')),
        if (onMap != null) Align(alignment: AlignmentDirectional.centerStart, child: Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton.icon(onPressed: onMap, icon: const Icon(Icons.map_outlined), label: const Text('الخريطة والملاحة')))),
        if (action != null) Align(alignment: AlignmentDirectional.centerEnd, child: Padding(padding: const EdgeInsets.only(top: 10), child: FilledButton(onPressed: busy ? null : onAction, child: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(action!.title))))
        else if (status == 'delivered') const Padding(padding: EdgeInsets.only(top: 10), child: Text('بانتظار تأكيد العميل للاستلام.')),
      ])),
    );
  }

  String _statusText(String status) => switch (status) {
    'available' => 'متاحة',
    'accepted' => 'مقبولة',
    'en_route_pickup' => 'في الطريق للاستلام',
    'picked_up' => 'تم الاستلام',
    'en_route_delivery' => 'في الطريق للعميل',
    'delivered' => 'تم التسليم',
    _ => status,
  };
}

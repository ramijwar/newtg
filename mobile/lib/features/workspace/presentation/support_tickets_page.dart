import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';

/// Customer support, deliberately provided as a first-class screen rather
/// than asking Android users to leave the app for the web portal.
final class SupportTicketsPage extends StatefulWidget {
  const SupportTicketsPage({super.key});

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

final class _SupportTicketsPageState extends State<SupportTicketsPage> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadMySupportTickets();
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SupportTicketEditorPage()),
    );
    if (created == true && mounted) {
      setState(() => _future = AppScope.of(context).loadMySupportTickets());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الدعم والمساعدة'),
          actions: [
            IconButton(
              tooltip: 'فتح تذكرة جديدة',
              onPressed: _openNew,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _TicketPlaceholder(
              icon: Icons.cloud_off_rounded,
              text: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل تذاكر الدعم.',
              button: 'إعادة المحاولة',
              onTap: () => setState(() => _future = AppScope.of(context).loadMySupportTickets()),
            );
            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            if (items.isEmpty) return _TicketPlaceholder(
              icon: Icons.support_agent_rounded,
              text: 'لا توجد تذاكر دعم مفتوحة.',
              button: 'فتح تذكرة',
              onTap: _openNew,
            );
            return RefreshIndicator(
              onRefresh: () async => setState(() => _future = AppScope.of(context).loadMySupportTickets()),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final ticket = items[index];
                  final id = ticket['public_id'] as String? ?? '';
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.support_agent_outlined, color: Theme.of(context).colorScheme.primary),
                      title: Text(ticket['subject'] as String? ?? 'تذكرة دعم', style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(_status(ticket['ticket_status'] as String? ?? 'open')),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: id.isEmpty ? null : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => SupportTicketDetailsPage(ticketId: id, subject: ticket['subject'] as String? ?? 'تذكرة دعم')),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );

  String _status(String status) => switch (status) {
    'open' => 'مفتوحة',
    'in_progress' => 'قيد المعالجة',
    'resolved' => 'تم الحل',
    'closed' => 'مغلقة',
    _ => status,
  };
}

final class SupportTicketEditorPage extends StatefulWidget {
  const SupportTicketEditorPage({super.key});
  @override
  State<SupportTicketEditorPage> createState() => _SupportTicketEditorPageState();
}

final class _SupportTicketEditorPageState extends State<SupportTicketEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;
  @override
  void dispose() { _subject.dispose(); _body.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).createSupportTicket(subject: _subject.text, body: _body.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تذكرة دعم جديدة')),
    body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('اشرح مشكلتك دون تضمين كلمات المرور أو رموز التحقق.', style: TextStyle(height: 1.6)),
      const SizedBox(height: 16),
      TextFormField(controller: _subject, maxLength: 180, decoration: const InputDecoration(labelText: 'عنوان المشكلة *'), validator: (value) => (value?.trim().length ?? 0) < 3 ? 'اكتب عنواناً واضحاً.' : null),
      const SizedBox(height: 9),
      TextFormField(controller: _body, minLines: 5, maxLines: 10, maxLength: 5000, decoration: const InputDecoration(labelText: 'التفاصيل *'), validator: (value) => (value?.trim().length ?? 0) < 3 ? 'اشرح المشكلة باختصار.' : null),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.send_rounded), label: Text(_saving ? 'جارٍ الإرسال…' : 'إرسال التذكرة')),
    ])),
  );
}

final class SupportTicketDetailsPage extends StatefulWidget {
  const SupportTicketDetailsPage({super.key, required this.ticketId, required this.subject});
  final String ticketId;
  final String subject;
  @override
  State<SupportTicketDetailsPage> createState() => _SupportTicketDetailsPageState();
}

final class _SupportTicketDetailsPageState extends State<SupportTicketDetailsPage> {
  late Future<Map<String, dynamic>> _future;
  final _reply = TextEditingController();
  bool _sending = false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _future = AppScope.of(context).loadSupportTicket(widget.ticketId); }
  @override
  void dispose() { _reply.dispose(); super.dispose(); }
  Future<void> _send() async {
    final text = _reply.text.trim(); if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try { await AppScope.of(context).replySupportTicket(ticketId: widget.ticketId, body: text); if (mounted) { _reply.clear(); setState(() => _future = AppScope.of(context).loadSupportTicket(widget.ticketId)); } }
    on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.subject)),
    body: Column(children: [
      Expanded(child: FutureBuilder<Map<String, dynamic>>(future: _future, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData) return _TicketPlaceholder(icon: Icons.cloud_off_rounded, text: 'تعذر تحميل المحادثة.', button: 'إعادة المحاولة', onTap: () => setState(() => _future = AppScope.of(context).loadSupportTicket(widget.ticketId)));
        final items = snapshot.data!['messages'] as List? ?? const [];
        return ListView.separated(padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
          final message = Map<String, dynamic>.from(items[index] as Map);
          return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: Text(message['body'] as String? ?? ''));
        });
      })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [
        Expanded(child: TextField(controller: _reply, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'أضف رسالة إلى التذكرة…'))),
        const SizedBox(width: 8), IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
      ]))),
    ]),
  );
}

final class _TicketPlaceholder extends StatelessWidget {
  const _TicketPlaceholder({required this.icon, required this.text, required this.button, required this.onTap});
  final IconData icon; final String text; final String button; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: onTap, child: Text(button))])));
}
